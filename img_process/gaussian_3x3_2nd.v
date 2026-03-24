`timescale 1ns/1ps
// 二阶 3×3 高斯：将 3×3 高斯模糊串联两级，实现更强的平滑（等效接近更大核的 sigma）。
// 吞吐仍为 1 像素/clk，固有延迟为两级窗口填充（约 2 行 + 2 行）。
module gaussian_3x3_2nd #(
    parameter DATA_W    = 8,
    parameter IMG_WIDTH = 1920
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 vs_in,
    input  wire                 hs_in,
    input  wire                 de_in,
    input  wire [DATA_W-1:0]    din,

    output wire                 vs_out,
    output wire                 hs_out,
    output wire                 de_out,
    output wire [DATA_W-1:0]    dout
);
    // 第一级
    wire vs1, hs1, de1;
    wire [DATA_W-1:0] d1;
    gaussian_3x3_stage #(
        .DATA_W(DATA_W),
        .IMG_WIDTH(IMG_WIDTH)
    ) u_stage1 (
        .clk    (clk),
        .rst_n  (rst_n),
        .vs_in  (vs_in),
        .hs_in  (hs_in),
        .de_in  (de_in),
        .din    (din),
        .vs_out (vs1),
        .hs_out (hs1),
        .de_out (de1),
        .dout   (d1)
    );

    // 第二级
    gaussian_3x3_stage #(
        .DATA_W(DATA_W),
        .IMG_WIDTH(IMG_WIDTH)
    ) u_stage2 (
        .clk    (clk),
        .rst_n  (rst_n),
        .vs_in  (vs1),
        .hs_in  (hs1),
        .de_in  (de1),
        .din    (d1),
        .vs_out (vs_out),
        .hs_out (hs_out),
        .de_out (de_out),
        .dout   (dout)
    );
endmodule