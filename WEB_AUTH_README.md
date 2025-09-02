# TeslaMate Web 访问控制功能

## 功能概述

为 TeslaMate Web 界面添加了密码访问控制功能，只有在输入正确密码后才能访问 TeslaMate 的 Web 界面。

## 配置方法

### 1. 设置访问密码

通过环境变量 `WEB_PASSWORD` 设置访问密码：

```bash
export WEB_PASSWORD="your_secure_password"
```

### 2. 在 Docker 中使用

如果使用 Docker 运行 TeslaMate，可以通过以下方式设置：

```yaml
# docker-compose.yml
environment:
  - WEB_PASSWORD=your_secure_password
```

或者在启动命令中：

```bash
docker run -e WEB_PASSWORD=your_secure_password teslamate/teslamate
```

### 3. 在系统服务中使用

在 systemd 服务文件中添加：

```ini
[Service]
Environment=WEB_PASSWORD=your_secure_password
```

## 功能特性

### 1. 密码保护

- 只有设置了 `WEB_PASSWORD` 环境变量时才会启用密码保护
- 如果未设置密码，Web 界面将正常开放访问
- 密码验证失败时会显示错误提示

### 2. 会话管理

- 认证成功后会在浏览器会话中保存认证状态
- 用户可以在导航栏点击"退出"按钮退出登录
- 退出后需要重新输入密码才能访问

### 3. 用户界面

- 提供简洁的密码输入界面
- 支持中文界面
- 显示 TeslaMate 品牌标识
- 提供使用说明

### 4. 安全性

- 密码通过环境变量配置，不会存储在代码中
- 使用 Phoenix 的会话管理机制
- 支持 HTTPS 环境下的安全传输

## 使用流程

1. **首次访问**：当设置了 `WEB_PASSWORD` 后，访问 TeslaMate Web 界面会自动跳转到密码输入页面
2. **输入密码**：在密码输入框中输入正确的密码
3. **认证成功**：密码正确后会跳转到 TeslaMate 主界面
4. **正常使用**：认证后可以正常使用所有 TeslaMate 功能
5. **退出登录**：点击导航栏的"退出"按钮可以退出登录

## 技术实现

### 核心模块

- `TeslaMate.WebAuth`：认证逻辑模块
- `TeslaMateWeb.Plugs.WebAuth`：认证中间件
- `TeslaMateWeb.WebAuthLive.Index`：密码输入页面

### 路由配置

- 主要页面通过 `:web_auth` 管道进行保护
- 认证页面 `/web_auth` 不需要认证即可访问

### 翻译支持

- 支持中文界面
- 所有用户界面文本都已翻译

## 注意事项

1. **密码安全**：请使用强密码，避免使用简单密码
2. **环境变量**：确保 `WEB_PASSWORD` 环境变量正确设置
3. **重启影响**：重启 TeslaMate 服务不会影响已认证的会话
4. **浏览器兼容**：支持现代浏览器的会话管理功能

## 故障排除

### 问题：设置了密码但仍然可以直接访问

**解决方案**：检查环境变量是否正确设置，重启 TeslaMate 服务

### 问题：密码输入后无法登录

**解决方案**：确认密码正确，检查浏览器控制台是否有错误信息

### 问题：退出登录后无法重新登录

**解决方案**：清除浏览器缓存和 Cookie，重新访问

## 更新日志

- **v1.0.0**：初始版本，支持基本的密码访问控制功能
