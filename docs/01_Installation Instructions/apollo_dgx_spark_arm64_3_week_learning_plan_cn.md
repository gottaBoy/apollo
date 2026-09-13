# DGX Spark ARM64 三周学习与练习计划

本计划适用于当前 `dgx-arm64` 分支和 DGX Spark ARM64 开发容器，时间为
2026 年 9 月 14 日至 2026 年 10 月 4 日，共 21 天，每天建议投入 1-3 小时。

三周目标是达到“能独立做局部模块开发”的水平：能运行现有组件、观察 Channel/Record、找 Bazel target、修改代码、编写测试、完成 CPU/NVIDIA 编译，并定位常见问题。基本 ROS2 概念不在本计划范围内，学习重点是 Apollo 实操。三周不可能覆盖 Apollo 全部算法细节，后续仍需按模块持续深入。

## 每天固定流程

宿主机执行：

```bash
cd /home/my/workspace/autodrive/apollo
git switch dgx-arm64
git status --short --branch
bash docker/scripts/dgx_spark_dev.sh start
bash docker/scripts/dgx_spark_dev.sh shell
```

容器内执行：

```bash
cd /apollo
uname -m
bazel --version
nvidia-smi -L
```

每天结束前执行：

```bash
git diff --check
git status --short
```

详细容器操作参见
[DGX Spark ARM64 源码开发指南](./apollo_dgx_spark_arm64_dev_guide_cn.md)。

## 第一周：环境、Bazel 和 CyberRT

目标：从“能启动和编译”达到“能运行、观察并修改一个 CyberRT target”。

| 天数 | 学习主题 | 练习 | 当天产物 |
| --- | --- | --- | --- |
| 第 1 天 | 跑通基线 | 启动容器，编译 `//cyber:cyber`，运行 `//cyber/common:file_test` | 保存基线耗时和输出 |
| 第 2 天 | 运行现有组件 | 编译并启动 `cyber/examples/common_component_example`，用 `cyber_monitor` 观察 | 找到组件的 Channel |
| 第 3 天 | 修改组件行为 | 修改示例日志、输出值或定时器周期，重启 launch 验证 | 观察到修改前后差异 |
| 第 4 天 | 追踪消息链路 | 用 `cyber_monitor`、`rg` 找到消息类型、发布者和订阅者 | 一张 Channel 追踪表 |
| 第 5 天 | Record 实操 | 使用 `cyber_recorder info/play/record` 记录或回放数据 | 一份 Record 调试记录 |
| 第 6 天 | 增加测试 | 修改已有 `_test.cc`，编译并运行精确 test target | 一个通过的测试提交 |
| 第 7 天 | 第一周验收 | 完成运行、观察、修改、测试、lint 和 Git 检查 | 一个可审查的小变更 |

第一周重点阅读：

```text
apollo.sh
scripts/apollo_base.sh
scripts/apollo_build.sh
cyber/node/
cyber/component/
cyber/message/
cyber/examples/
cyber/mainboard/
```

## 第二周：模块和自动驾驶数据链路

目标：围绕真实模块完成“输入、处理、输出、测试”的修改闭环。

| 天数 | 学习主题 | 练习 | 当天产物 |
| --- | --- | --- | --- |
| 第 8 天 | Common/Proto | 找到一个实际消息的定义、BUILD、生产者和消费者 | 消息链路图 |
| 第 9 天 | Localization | 构建模块，追踪定位输出，修改日志或测试点 | 定位模块回归结果 |
| 第 10 天 | Perception CPU | 选择较小子目录，查询 target 并完成 CPU 构建 | 一个最小感知 target |
| 第 11 天 | Perception GPU | 查询 inference target，尝试 NVIDIA 构建并记录依赖错误 | CUDA/TensorRT 依赖表 |
| 第 12 天 | Prediction | 追踪 Evaluator/Predictor，修改边界处理并跑测试 | 一个预测测试变更 |
| 第 13 天 | Planning | 追踪 `ADCTrajectory` 生成，修改一个 Task/测试点 | 一条 Planning 调用链 |
| 第 14 天 | 第二周验收 | 选择一个模块完成编译、测试、lint 和提交 | 一份模块级小变更 |

推荐命令：

```bash
bazel query //modules/localization/...
bazel query //modules/prediction/...
bazel query //modules/planning/...
bash apollo.sh build_cpu localization
bash apollo.sh build_cpu prediction
bash apollo.sh build_cpu planning
```

推荐阅读：

```text
modules/common_msgs/
modules/localization/
modules/perception/
modules/prediction/
modules/planning/
docs/05_Localization/
docs/06_Perception/
docs/07_Prediction/
docs/08_Planning/
```

第二周不要直接构建整个 Apollo；先查询目录，再选择最小 target。每个模块都回答：入口 Component、输入 Channel、核心处理函数、配置文件、输出消息、BUILD target 和测试在哪里。

## 第三周：GPU、调试和综合开发

目标：能处理 GPU、日志、链接、测试失败，并完成一个综合小项目。

| 天数 | 学习主题 | 练习 | 当天产物 |
| --- | --- | --- | --- |
| 第 15 天 | GPU 探测和编译 | `apollo.sh config`、`build_nvidia cyber`、检查 `nvidia-smi` | 确认 NVIDIA 构建链路 |
| 第 16 天 | GPU 配置测试 | 执行 NVIDIA 测试，确认测试是否实际调用 GPU | 一份 GPU 测试记录 |
| 第 17 天 | 依赖问题定位 | 使用 `bazel query`、`ldconfig`、`ldd` 缩小 CUDA/TensorRT 问题 | 一份失败归因记录 |
| 第 18 天 | 调试运行时 | `build_dbg`、`--verbose_failures`、GDB、日志和线程栈 | 一次问题定位过程 |
| 第 19 天 | 质量和提交 | lint、diff、生成文件检查，整理提交 | 一个干净的 Git 提交 |
| 第 20 天 | 综合小项目 | 完成一个组件、测试增强或模块小修复 | CPU/NVIDIA 双配置结果 |
| 第 21 天 | 最终验收 | 编译、测试、lint、Git 和容器隔离检查 | 一份可审查的完整变更 |

第三周核心命令：

```bash
nvidia-smi -L
bash apollo.sh config
bash apollo.sh build_nvidia cyber
bash apollo.sh test --config=nvidia cyber
bash apollo.sh build_dbg cyber
bash apollo.sh lint --cpp
```

GPU 相关模块建议从查询开始：

```bash
bazel query --config=nvidia //modules/perception/common/inference/...
bazel build --config=nvidia //modules/perception/common/inference/...
```

`--config=nvidia` 只表示选择 NVIDIA 编译配置，不保证每个测试 target 都实际调用 CUDA、TensorRT 或 GPU 设备。

## 综合项目建议

选择以下一个项目完成：

1. **CyberRT 测试增强**：为现有测试增加一个边界条件和失败信息。
2. **错误处理改进**：为一个模块错误路径增加日志，并补充测试。
3. **GPU 目标验证**：选择一个 perception 推理子目录，完成 CPU/NVIDIA 构建对比并记录依赖问题。
4. **消息监控组件**：订阅一个 Apollo 消息，检查字段范围或时间戳，发布检查结果并编写测试。

最低验收命令：

```bash
bash apollo.sh build_cpu cyber
bash apollo.sh test --config=cpu cyber
bash apollo.sh build_nvidia cyber
bash apollo.sh test --config=nvidia cyber
bash apollo.sh lint --cpp
git diff --check
git status --short
```

## 源码阅读方法

每读一个模块，固定回答以下问题：

```text
1. 入口 Component 是什么？
2. 输入 Channel 和消息类型是什么？
3. 核心处理函数是什么？
4. 使用哪些配置、DAG 和 launch 文件？
5. 输出消息和 Channel 是什么？
6. BUILD target 和测试在哪里？
7. 如何启动、观察和复现？
```

常用搜索：

```bash
rg -n 'CYBER_REGISTER_COMPONENT|CreateReader|CreateWriter|Proc\(|Init\(' modules/<module>
rg -n 'cc_test|sh_test|py_test' modules/<module>
rg -n 'LocalizationEstimate|PerceptionObstacles|ADCTrajectory|ControlCommand' modules
```

## 三周后的能力边界

达到以下标准即可进入模块专项学习：

- 能独立启动、进入和停止隔离容器。
- 能从源码找到 Bazel target、BUILD、配置和测试。
- 能完成 CPU/NVIDIA 编译和单元测试。
- 能增加局部功能或测试，并提交干净变更。
- 能使用日志、详细失败输出、动态库和基础调试工具定位问题。
- 能解释 GPU 编译配置与实际 GPU 运行的区别。

后续可选择 CyberRT、感知/TensorRT、Prediction、Planning、Control 或 Bazel 工程化方向继续深入。三周建立的是完整源码导航和开发闭环，不等同于掌握 Apollo 全部算法；单个专业模块通常还需要数周到数月的持续实践。
