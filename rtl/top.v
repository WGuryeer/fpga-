`timescale 1ns / 1ps
`define UD #1

// 顶层：
// 1) 产生 I2C 配置时钟并初始化 MS72xx（HDMI Rx / Tx）。
// 2) 将 MS7200 输出的 RGB 数据门控后送入灰度化模块 rgb2gray，供后续算法使用。
// 3) 保留直通输出口（当前仅在 init_over 后透传；可用于旁路显示或调试）。
module top(
    input  wire        sys_clk,     // 50MHz 系统时钟

    output             rstn_out,    // 下游复位（高有效）
    // I2C 接口（MS7200 Rx / Tx）
    output             iic_scl,
    inout              iic_sda,
    output             iic_tx_scl,
    inout              iic_tx_sda,

    // HDMI→MS7200 解码后的并口输入
    input              pixclk_in,
    input              vs_in,
    input              hs_in,
    input              de_in,
    input      [7:0]   r_in,
    input      [7:0]   g_in,
    input      [7:0]   b_in,

    // 透传输出（可接显示/ILA），init_over 之前保持 0
    output             pixclk_out,
    output reg         vs_out,
    output reg         hs_out,
    output reg         de_out,
    output reg  [7:0]  r_out,
    output reg  [7:0]  g_out,
    output reg  [7:0]  b_out,

    // 灰度化输出，供算法管线使用
    output             vs_gray,
    output             hs_gray,
    output             de_gray,
    output      [7:0]  gray_out,

    output             led_int     // 指示初始化完成
);

    // === 1080p 时序参数（备用/留作扩展） ===
    parameter V_TOTAL  = 12'd1125;
    parameter V_FP     = 12'd4;
    parameter V_BP     = 12'd36;
    parameter V_SYNC   = 12'd5;
    parameter V_ACT    = 12'd1080;
    parameter H_TOTAL  = 12'd2200;
    parameter H_FP     = 12'd88;
    parameter H_BP     = 12'd148;
    parameter H_SYNC   = 12'd44;
    parameter H_ACT    = 12'd1920;

    // === 时钟 & 复位 ===
    reg  [15:0] rstn_1ms;
    wire        cfg_clk;   // I2C 逻辑时钟（约 10MHz）
    wire        locked;    // PLL 锁定
    PLL u_pll (
        .clkin1   (sys_clk),  // 50MHz in
        .pll_lock (locked),
        .clkout0  (cfg_clk)   // 10MHz out
    );

    // 1ms 级延时，上电后等待 PLL 锁定再释放 rstn_out
    always @(posedge cfg_clk) begin
        if(!locked)
            rstn_1ms <= 16'd0;
        else if(rstn_1ms != 16'h2710)
            rstn_1ms <= rstn_1ms + 1'b1;
    end
    assign rstn_out = (rstn_1ms == 16'h2710);

    // === MS72xx 初始化控制 ===
    wire init_over;  // 初始化完成标志
    ms72xx_ctl u_ms72xx_ctl (
        .clk        (cfg_clk),
        .rst_n      (rstn_out),
        .init_over  (init_over),
        .iic_tx_scl (iic_tx_scl),
        .iic_tx_sda (iic_tx_sda),
        .iic_scl    (iic_scl),
        .iic_sda    (iic_sda)
    );

    assign led_int   = init_over;
    assign pixclk_out = pixclk_in; // 像素时钟透传

    // === RGB 透传：init_over 前拉低 ===
    always @(posedge pixclk_out) begin
        if(!init_over) begin
            vs_out <= 1'b0;
            hs_out <= 1'b0;
            de_out <= 1'b0;
            r_out  <= 8'd0;
            g_out  <= 8'd0;
            b_out  <= 8'd0;
        end else begin
            vs_out <= vs_in;
            hs_out <= hs_in;
            de_out <= de_in;
            r_out  <= r_in;
            g_out  <= g_in;
            b_out  <= b_in;
        end
    end

	/////////////////////////////////////////////////////////////////////////
	//                             图像处理算法管线
	//  灰度化----2阶33高斯模糊----Sobel_X 水平边缘检测----二值化阈值
	/////////////////////////////////////////////////////////////////////////
	
	
    // === 灰度化：RGB → Gray，供算法管线输入 ===
    // 直接使用 MS7200 输出，保持与 pixclk_out 同步；复位由 init_over 解除
    rgb2gray #(
        .IN_WIDTH (8),
        .OUT_WIDTH(8)
    ) u_rgb2gray (
        .clk     (pixclk_out),
        .rst_n   (init_over), // 初始化完成后释放
        .vs_in   (vs_in),
        .hs_in   (hs_in),
        .de_in   (de_in),
        .r_in    (r_in),
        .g_in    (g_in),
        .b_in    (b_in),
        .vs_out  (vs_gray),
        .hs_out  (hs_gray),
        .de_out  (de_gray),
        .gray_out(gray_out)
    );

	
    // === 二阶 3×3 高斯（替换原先的 5×5）===
    gaussian_3x3_2nd #(
        .DATA_W   (8),
        .IMG_WIDTH(1920)
    ) u_gaussian_3x3_2nd (
        .clk    (pixclk_out),
        .rst_n  (init_over),
        .vs_in  (vs_gray),
        .hs_in  (hs_gray),
        .de_in  (de_gray),
        .din    (gray_out),
        .vs_out (vs_gauss),   // 供后续 Sobel/算法使用
        .hs_out (hs_gauss),
        .de_out (de_gauss),
        .dout   (gauss_out)
    );
	
	// ===Sobel_X 水平边缘检测===
	//核心是对 X 方向求导（差分），对 Y 方向用 1‑2‑1 做平滑抑制噪声。
	//响应强的区域即图像中“竖直边缘”
    wire        vs_sobel, hs_sobel, de_sobel;
    wire signed [10:0] gx_raw;
    wire        [10:0] gx_abs;
    wire        [7:0]  sobel_disp;
    wire                edge_flag;

    sobel_x #(
        .DATA_W   (8),
        .IMG_WIDTH(1920),
        .THRESH   (11'd80),
        .SCALE_SH (2)      // 1020 -> 255
    ) u_sobel_x (
        .clk      (pixclk_out),
        .rst_n    (init_over),
        .vs_in    (vs_gauss),
        .hs_in    (hs_gauss),
        .de_in    (de_gauss),
        .din      (gauss_out),
        .vs_out   (vs_sobel),
        .hs_out   (hs_sobel),
        .de_out   (de_sobel),
        .gx_raw   (gx_raw),
        .gx_abs   (gx_abs),
        .sobel_disp(sobel_disp),
        .edge_flag(edge_flag)
    );
    // 后续形态学/阈值处理可使用 sobel_disp 或 gx_abs

endmodule