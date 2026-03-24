`timescale 1ns/1ps
// 单阶段 3×3 高斯模糊（权值 1 2 1 / 2 4 2 / 1 2 1，总和 16）
// 仅需 2 行行缓，1 像素/clk 吞吐。
module gaussian_3x3_stage #(
    parameter DATA_W    = 8,
    parameter IMG_WIDTH = 1920
)(
    input  wire                 clk,
    input  wire                 rst_n,   // 同步低有效
    input  wire                 vs_in,
    input  wire                 hs_in,
    input  wire                 de_in,
    input  wire [DATA_W-1:0]    din,

    output reg                  vs_out,
    output reg                  hs_out,
    output reg                  de_out,
    output reg  [DATA_W-1:0]    dout
);
    // 行缓
    reg [DATA_W-1:0] linebuf0 [0:IMG_WIDTH-1]; // row-1
    reg [DATA_W-1:0] linebuf1 [0:IMG_WIDTH-1]; // row-2

    reg [$clog2(IMG_WIDTH)-1:0] col;
    always @(posedge clk) begin
        if(!rst_n || !de_in) col <= 0;
        else                 col <= col + 1'b1;
    end

    // 3×3 窗口
    reg [DATA_W-1:0] p00,p01,p02,
                     p10,p11,p12,
                     p20,p21,p22;
    always @(posedge clk) begin
        if(!rst_n) begin
            {p00,p01,p02,p10,p11,p12,p20,p21,p22} <= 0;
        end else if(de_in) begin
            p00 <= linebuf1[col];
            p10 <= linebuf0[col];
            p20 <= din;
            p01 <= p00; p02 <= p01;
            p11 <= p10; p12 <= p11;
            p21 <= p20; p22 <= p21;
            linebuf1[col] <= linebuf0[col];
            linebuf0[col] <= din;
        end
    end

    // 卷积：乘2=左移1，乘4=左移2
    wire [DATA_W+3:0] sum_row0 = {2'b0,p00} + ({1'b0,p01}<<1) + {2'b0,p02};
    wire [DATA_W+3:0] sum_row1 = ({1'b0,p10}<<1) + ({2'b0,p11}<<2) + ({1'b0,p12}<<1);
    wire [DATA_W+3:0] sum_row2 = {2'b0,p20} + ({1'b0,p21}<<1) + {2'b0,p22};
    wire [DATA_W+5:0] sum      = sum_row0 + sum_row1 + sum_row2;

    // 归一化（除以16，四舍五入）
    wire [DATA_W-1:0] blur = (sum + 6'd8) >> 4;

    // 窗口有效：行列>=1
    wire win_valid = de_in && (col >= 1);

    always @(posedge clk) begin
        if(!rst_n) begin
            vs_out <= 1'b0;
            hs_out <= 1'b0;
            de_out <= 1'b0;
            dout   <= 0;
        end else begin
            vs_out <= vs_in;
            hs_out <= hs_in;
            de_out <= win_valid;
            dout   <= win_valid ? blur : 0;
        end
    end
endmodule