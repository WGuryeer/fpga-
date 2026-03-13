# FPGA 项目

自用 FPGA / IC 设计工作空间。

## 目录结构

```
fpga-/
├── src/          # RTL 源代码（Verilog / VHDL）
├── sim/          # 仿真测试文件
├── constraints/  # 约束文件（XDC / SDC）
├── ip/           # IP 核文件
├── scripts/      # 构建 / 综合脚本
└── docs/         # 设计文档
```

## 使用说明

1. 将 RTL 源文件放置于 `src/` 目录。
2. 将仿真文件放置于 `sim/` 目录。
3. 将时序及引脚约束文件放置于 `constraints/` 目录。
4. 使用 `scripts/` 中的脚本完成综合与实现。
