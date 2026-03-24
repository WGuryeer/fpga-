`timescale 1ns/1ps
// 功能：将输入的 RGB888 流转换为灰度流，保持行场同步信号对齐。
// 公式：Gray = 0.299*R + 0.587*G + 0.114*B
// 实现：用整数近似系数 77/256, 150/256, 29/256，乘法后右移 8 位（等价除以 256）。
module rgb2gray #(
    parameter IN_WIDTH  = 8,  // 输入每通道位宽，默认 8bit
    parameter OUT_WIDTH = 8   // 输出灰度位宽，默认 8bit
)(
    input  wire                 clk,     // 像素时钟，与输入数据同域
    input  wire                 rst_n,   // 同步低有效复位

    // 输入：行场同步与有效信号 + RGB 数据
    input  wire                 vs_in,   // 场同步（frame/field sync）
    input  wire                 hs_in,   // 行同步（line sync）
    input  wire                 de_in,   // 数据有效（Data Enable）
    input  wire [IN_WIDTH-1:0]  r_in,    // Red  通道
    input  wire [IN_WIDTH-1:0]  g_in,    // Green通道
    input  wire [IN_WIDTH-1:0]  b_in,    // Blue 通道

    // 输出：与输入同步对齐的行场/有效 + 灰度数据
    output reg                  vs_out,
    output reg                  hs_out,
    output reg                  de_out,
    output reg  [OUT_WIDTH-1:0] gray_out // 灰度值
);
    // ---------------------- 乘法与加权 ----------------------
    // 乘法结果宽度：8bit * 8bit = 16bit，防止溢出
    // 系数选取：0.299≈77/256, 0.587≈150/256, 0.114≈29/256
    wire [15:0] mult_r = r_in * 8'd77;   // 77 * R
    wire [15:0] mult_g = g_in * 8'd150;  // 150 * G
    wire [15:0] mult_b = b_in * 8'd29;   // 29 * B

    // 求和后右移 8 位，相当于除以 256，实现灰度加权平均
    wire [17:0] sum  = mult_r + mult_g + mult_b; // 最大值 255*150*3 ≈ 114k，18 位足够
    wire [7:0]  gray = sum[15:8];                // 取高 8 位，相当于 sum >> 8

    // ---------------------- 时序与复位 ----------------------
    always @(posedge clk) begin
        if(!rst_n) begin
            vs_out   <= 1'b0;
            hs_out   <= 1'b0;
            de_out   <= 1'b0;
            gray_out <= {OUT_WIDTH{1'b0}};
        end else begin
            // 将同步信号一拍延迟，与灰度数据保持对齐
            vs_out   <= vs_in;
            hs_out   <= hs_in;
            de_out   <= de_in;
            gray_out <= gray;  // 灰度输出
        end
    end
endmodule