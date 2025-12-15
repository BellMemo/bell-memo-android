# BellMemo

一个简单的 Flutter 演示应用。

## 📋 项目简介

BellMemo 是一个基于 Flutter 开发的备忘录应用, 并且支持简单的网盘功能.

## 🛠️ 环境要求

- Flutter SDK >= 3.0.0
- Dart SDK >= 3.0.0
- Android Studio / VS Code（推荐）
- Android SDK（用于 Android 平台开发）

## 📦 安装步骤

### 1. 克隆项目

```bash
git clone <repository-url>
cd bell-memo-android
```

### 2. 检查 Flutter 环境

```bash
flutter doctor
```

确保所有必要的工具都已正确安装。

### 3. 获取依赖

```bash
flutter pub get
```

### 4. 运行项目

```bash
# 在 Android 设备或模拟器上运行
flutter run

# 查看可用的设备
flutter devices

# 在特定设备上运行
flutter run -d <device-id>
```

## 📁 项目结构

```
lib/
  app/
    app.dart            # MaterialApp / theme / routes
    bootstrap.dart      # main() 入口初始化（可选）
  features/
    splash/
      presentation/
        splash_screen.dart
    memo/
      domain/
        memo.dart
      data/
        memo_service.dart        # 或 memo_repository.dart / datasource
      presentation/
        memo_page.dart
        memo_edit_page.dart
        memo_provider.dart       # 或 bloc/cubit/notifier
    cloud/
      presentation/
        cloud_storage_page.dart
    settings/
      presentation/
        settings_page.dart
    shell/
      presentation/
        home_page.dart           # 导航壳（抽屉/底部导航）
  shared/
    widgets/                     # 通用组件
    utils/                       # 工具方法
```

## 🎨 功能特性

- ✅ Flutter 跨平台支持
- ✅ Material Design 3 设计
- ✅ 保留原有桌面图标设计
- ✅ 简洁的演示界面

## 🚀 开发指南

### 代码规范

项目遵循以下代码规范：
- 遵循官方 [Dart 风格指南](https://dart.dev/guides/language/effective-dart/style)
- 使用 `flutter_lints` 进行代码检查
- 详细规范请参考 [.cursor/rules/main.mdc](.cursor/rules/main.mdc)

### Git 提交规范

项目使用 [Conventional Commits](https://www.conventionalcommits.org/) 规范：

```
<类型>(<范围>): <主题>

<正文>

<脚注>
```

提交类型：
- `feat`: 新功能
- `fix`: 修复 bug
- `docs`: 文档变更
- `refactor`: 代码重构
- `style`: 代码格式调整
- `test`: 测试相关
- `chore`: 构建过程或辅助工具的变动

示例：
```
feat(ui): 添加用户登录页面

实现了用户登录界面，包括用户名和密码输入框。

Closes #123
```

**重要提示**：如果改动较大（如新增主要功能、架构变更等），必须同步更新 README.md。

### 运行测试

```bash
# 运行所有测试
flutter test

# 运行特定测试文件
flutter test test/example_test.dart
```

### 代码检查

```bash
# 分析代码
flutter analyze

# 格式化代码
dart format lib/
```

## 📱 平台支持

- ✅ Android
- ⏳ iOS（待支持）
- ⏳ Web（待支持）
- ⏳ Desktop（待支持）

## 🔧 构建发布

### Android APK

```bash
# 构建调试版本
flutter build apk --debug

# 构建发布版本
flutter build apk --release

# 构建 App Bundle（推荐用于 Google Play）
flutter build appbundle --release
```

## 📄 许可证

查看 [LICENSE](LICENSE) 文件了解详情。

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📚 相关资源

- [Flutter 官方文档](https://docs.flutter.dev/)
- [Dart 语言指南](https://dart.dev/guides)
- [Flutter 示例代码](https://docs.flutter.dev/cookbook)
- [Material Design 3](https://m3.material.io/)

## 📝 更新日志

### v1.0.0+1 (当前版本)
- ✅ 项目重构为 Flutter 应用
- ✅ 保留原有桌面图标设计
- ✅ 创建基础演示界面
- ✅ 配置 Android 平台支持
