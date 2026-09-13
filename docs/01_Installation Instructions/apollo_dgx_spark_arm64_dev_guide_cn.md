# DGX Spark ARM64 源码开发指南

本文档记录在 NVIDIA DGX Spark（`aarch64`）上使用 Apollo 源码开发容器的流程。
该流程使用 `docker/scripts/dgx_spark_dev.sh`，不复用 Apollo 默认的开发容器、配置或地图/音频数据卷。

## 前置条件

- Linux 主机，CPU 架构为 `aarch64`。
- Docker 服务正常运行。
- NVIDIA Container Toolkit/CDI 可用；GPU 模式需要宿主机能执行 `nvidia-smi`。
- 当前仓库已切换到 `dgx-arm64` 分支。

```bash
cd /home/my/workspace/autodrive/apollo
git switch dgx-arm64
```

## 启动和进入容器

查看完整用法：

```bash
bash docker/scripts/dgx_spark_dev.sh --help
```

默认启动 GPU 开发容器。脚本优先使用 NVIDIA CDI，并默认只注入 GPU `0`：

```bash
bash docker/scripts/dgx_spark_dev.sh start
```

只启动 CPU 容器，不注入 GPU：

```bash
bash docker/scripts/dgx_spark_dev.sh --cpu start
```

进入已运行的容器：

```bash
bash docker/scripts/dgx_spark_dev.sh shell
```

查看状态和隔离挂载：

```bash
bash docker/scripts/dgx_spark_dev.sh status
```

停止当前 harness 创建的容器：

```bash
bash docker/scripts/dgx_spark_dev.sh stop
```

`--cpu` 只控制 Docker 容器是否注入 GPU，不会自动添加 Bazel 的 CPU 编译配置。
容器已经存在时，`start` 会复用已有容器，不会改变它的 GPU/CPU 模式。需要同时保留两种模式时使用不同名称：

```bash
bash docker/scripts/dgx_spark_dev.sh --name apollo_dgx_cpu --cpu start
bash docker/scripts/dgx_spark_dev.sh --name apollo_dgx_gpu start
```

## 隔离策略

- 源码以读写方式挂载到容器 `/apollo`，便于直接编辑和编译。
- 配置、HOME、Bazel 缓存和运行数据分别放在仓库下的 `.dgx-spark/`。
- `.dgx-spark/` 已加入 `.gitignore`，不会进入 Git 工作区。
- 容器使用 bridge 网络、private IPC，且不使用 `--privileged`、host 网络或 host PID。
- 不使用 `~/.apollo`，不创建或重建 Apollo 默认 map/audio 数据卷。
- `stop` 只停止当前配置的容器，不操作其它 Docker 容器。
- 进入 shell 时会清除镜像内失效的 `localhost:58001` 代理变量，避免 Bazel 下载依赖时误连容器自身。

默认容器名为 `apollo_dgx_spark_${USER}`。默认 ARM64 镜像标签为：

```text
apolloauto/apollo:dev-aarch64-20.04-20240626_1642
```

如果本地只有中国镜像源标签，脚本会复用已存在的：

```text
registry.baidubce.com/apolloauto/apollo:dev-aarch64-20.04-20240626_1642
```

脚本不会自动拉取镜像。

## CPU 编译

进入容器后，推荐使用 Apollo 封装命令：

```bash
bash apollo.sh build_cpu cyber
```

该命令会选择 CPU 构建，并在 ARM64 上设置必要的本地架构和 PIC 编译参数。

直接使用 Bazel 验证单个目标时，可以执行：

```bash
bazel query //cyber:cyber --output=label
bazel build --config=cpu //cyber:cyber
bazel build --config=cpu //cyber/mainboard:mainboard
```

`--config=cpu` 表示 Bazel 使用 CPU 配置；对于完整模块构建，优先使用
`bash apollo.sh build_cpu <module>`，因为 Apollo 脚本还会处理 GPU 目标裁剪和 ARM64 编译参数。

## NVIDIA GPU 编译

先确认容器能访问 GPU：

```bash
nvidia-smi -L
```

推荐使用 Apollo 封装命令构建 CyberRT：

```bash
bash apollo.sh build_nvidia cyber
```

`build_gpu` 也可以使用：

```bash
bash apollo.sh build_gpu cyber
```

当前仓库的 `--config=gpu` 会展开到 NVIDIA 配置。完成环境初始化后，也可以直接使用 Bazel：

```bash
bazel query --config=nvidia //cyber:cyber --output=label
bazel build --config=nvidia //cyber:cyber
```

CPU 和 GPU 配置不要混用：

```text
--config=cpu 与 --config=gpu 不要同时使用
--config=cpu 与 --config=nvidia 不要同时使用
```

本分支的 ARM64 GPU 探测同时支持两种环境：Jetson 的 `nvgpu` 内核模块，以及
DGX Spark 的 `nvidia-smi -L`、CUDA runtime 组合。因此容器有 GPU 时，Apollo 应显示：

```text
USE_GPU_TARGET: 1
GPU_PLATFORM: NVIDIA
```

如果显示 `USE_GPU_TARGET: 0`，先确认使用的是本分支的 `scripts/apollo.bashrc`，并检查
`nvidia-smi -L` 和 `ldconfig -p | grep cudart`。

## 当前验证结果

在 2026-09-13 的 DGX Spark 环境中已验证：

- `bazel query //cyber:cyber` 成功。
- `bash apollo.sh build_cpu cyber` 成功。
- `bash apollo.sh build_nvidia cyber` 成功，并识别为 `NVIDIA GPU` 构建。
- `//cyber/mainboard:mainboard` CPU 编译和链接成功。

首次开发建议先验证 `cyber`，再逐步构建感知、推理等 CUDA/TensorRT 依赖更重的模块。
Apollo 现有部分 ARM64 第三方依赖仍带有旧 Jetson/CUDA/TensorRT 假设，完整模块构建需要单独验证。

更多通用 CPU/GPU 构建说明参见
[Apollo 构建和测试说明](./apollo_build_and_test_explained.md)。
