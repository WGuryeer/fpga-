`timescale 1ns/1ps
// 流式 Sobel X（水平梯度，检测竖直边缘）
// 输入建议接 gaussian_3x3_2nd 的输出：vs_gauss / hs_gauss / de_gauss / gauss_out
// 特点：
//   - 3×3 Sobel 核：
//       +1  0  -1
//       +2  0  -2
//       +1  0  -1
//   - 仅需 2 行行缓，1 像素/clk 吞吐；固有窗口延迟约 2 行。
//   - 输出：带符号梯度 gx_raw，绝对值 gx_abs，8bit 可视化 sobel_disp（|Gx| 近似归一化），edge_flag 阈值判决。
// 说明：乘 2 用移位，系数固定常量，不占 DSP（综合器可能仍用 DSP 以跑频）。
module sobel_x #(
    parameter DATA_W    = 8,        // 输入灰度位宽
    parameter IMG_WIDTH = 1920,     // 行像素数
    parameter THRESH    = 11'd80,   // |Gx| 阈值
    parameter SCALE_SH  = 2         // 归一化右移位数：1020>>2≈255，用于 sobel_disp
)(
    input  wire                 clk,
    input  wire                 rst_n,   // 同步低有效

    input  wire                 vs_in,
    input  wire                 hs_in,
    input  wire                 de_in,
    input  wire [DATA_W-1:0]    din,     // 灰度输入（来自二阶 3×3 高斯）

    output reg                  vs_out,
    output reg                  hs_out,
    output reg                  de_out,
    output reg  signed [10:0]   gx_raw,      // 带符号梯度 [-1020,1020]
    output reg         [10:0]   gx_abs,      // 绝对值
    output reg         [7:0]    sobel_disp,  // 8bit 可视化（|Gx| 右移 SCALE_SH，带饱和）
    output reg                  edge_flag    // |Gx| >= THRESH 时为 1
);
    // ------------ 行缓：2 行 ------------
    (* ram_style="block" *) reg [DATA_W-1:0] linebuf0 [0:IMG_WIDTH-1]; // row-1
    (* ram_style="block" *) reg [DATA_W-1:0] linebuf1 [0:IMG_WIDTH-1]; // row-2

    // 列计数（仅在 de_in 期间递增）
    reg [$clog2(IMG_WIDTH)-1:0] col;
    always @(posedge clk) begin
        if(!rst_n || !de_in) col <= 0;
        else                 col <= col + 1'b1;
    end

    // 行计数：在每行结束时 +1；用 hs 的下降沿检测
    reg hs_d;
    always @(posedge clk) hs_d <= hs_in;

    reg [15:0] row_cnt;
    always @(posedge clk) begin
        if(!rst_n || vs_in)          row_cnt <= 0;               // 新帧
        else if(hs_d && !hs_in)      row_cnt <= row_cnt + 1'b1;  // 行结束
    end

    // 3×3 窗口移位寄存
    reg [DATA_W-1:0] p00,p01,p02,
                     p10,p11,p12,
                     p20,p21,p22;

    always @(posedge clk) begin
        if(!rst_n) begin
            {p00,p01,p02,p10,p11,p12,p20,p21,p22} <= 0;
        end else if(de_in) begin
            // 同列三行取值
            p00 <= linebuf1[col]; // row-2
            p10 <= linebuf0[col]; // row-1
            p20 <= din;           // row 0
            // 列方向右移形成三列
            p01 <= p00; p02 <= p01;
            p11 <= p10; p12 <= p11;
            p21 <= p20; p22 <= p21;
            // 行缓滚动写入
            linebuf1[col] <= linebuf0[col];
            linebuf0[col] <= din;
        end
    end

    // ------------ Sobel X 计算 ------------
    // 左列 (p00,p01,p02) 与右列 (p20,p21,p22) 权重 1/2/1
    wire signed [10:0] left_sum  = {3'b0,p00} + ({2'b0,p01}<<1) + {3'b0,p02};
    wire signed [10:0] right_sum = {3'b0,p20} + ({2'b0,p21}<<1) + {3'b0,p22};
    wire signed [10:0] gx_calc   = right_sum - left_sum; // 范围 [-1020,1020]

    wire [10:0] gx_abs_w = gx_calc[10] ? (~gx_calc + 1'b1) : gx_calc;

    // 可视化缩放：右移 SCALE_SH，超 8bit 饱和
    wire [7:0] scaled = gx_abs_w[10:SCALE_SH];
    wire       sat    = |gx_abs_w[10:8+SCALE_SH]; // 超出 8bit 检测

    // 窗口有效：至少 2 行、2 列且 de_in=1
    wire win_valid = de_in && (col >= 2) && (row_cnt >= 2);

    // ------------ 输出寄存 ------------
    always @(posedge clk) begin
        if(!rst_n) begin
            vs_out     <= 1'b0;
            hs_out     <= 1'b0;
            de_out     <= 1'b0;
            gx_raw     <= 11'sd0;
            gx_abs     <= 11'd0;
            sobel_disp <= 8'd0;
            edge_flag  <= 1'b0;
        end else begin
            vs_out <= vs_in;
            hs_out <= hs_in;
            de_out <= win_valid;

            gx_raw <= gx_calc;
            gx_abs <= gx_abs_w;

            sobel_disp <= win_valid ? (sat ? 8'hFF : scaled) : 8'd0;
            edge_flag  <= win_valid && (gx_abs_w >= THRESH);
        end
    end
endmodule