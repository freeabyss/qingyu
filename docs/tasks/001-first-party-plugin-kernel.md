# Task 001：第一方插件内核

**目标：** 建立仅供内置模块使用的插件契约、注册表和动作路由，不改变现有用户行为。

**范围：** 插件元数据、能力清单、搜索源、设置页、菜单、快捷键、权限声明、启停生命周期与动作执行。

**相关模块：** `AppContainer`、`SearchCore`、`GlobalShortcutManager`、`StatusItemController`。

**业务规则：** 插件只从代码注册；标识唯一；单插件启动失败不阻断其他插件；停用时注销贡献并停止任务。

**技术约束：** 所有插件和注册表在 `@MainActor`；不扫描磁盘、不加载 Bundle；动作使用稳定 ID，不用通知字符串作为插件 API。

**验收标准：** 重复 ID 被拒绝；贡献按插件查询；动作只由所属插件执行；启动失败被记录并隔离；停用后贡献不可见。

## 文件

- 新建：`Qingniao/Plugins/Core/PluginTypes.swift`
- 新建：`Qingniao/Plugins/Core/PluginRegistry.swift`
- 修改：`Qingniao/App/Controllers/AppContainer.swift`
- 修改：`Qingniao.xcodeproj/project.pbxproj`
- 新建：`docs/decisions/ADR-001-first-party-plugin-model.md`
- 修改：`docs/architecture/design.md`、`docs/architecture/api.md`
- 测试：`QingniaoTests/PluginRegistryTests.swift`

## 接口

```swift
struct PluginID: RawRepresentable, Hashable, Codable { let rawValue: String }
struct PluginActionID: RawRepresentable, Hashable, Codable { let rawValue: String }

struct PluginDescriptor {
    let id: PluginID
    let displayNameKey: String
    let version: String
    let defaultEnabled: Bool
}

struct PluginSettingsPageDescriptor {
    let id: PluginID
    let titleKey: String
    let systemImageName: String
    let order: Int
    let makeView: @MainActor () -> AnyView
}

struct PluginAction {
    let id: PluginActionID
    let perform: @MainActor () async throws -> Void
}

struct PluginManifest {
    let descriptor: PluginDescriptor
    let searchSources: [any SearchSource]
    let actions: [PluginAction]
    let settingsPage: PluginSettingsPageDescriptor?
    let menuItems: [PluginMenuItemDescriptor]
    let shortcuts: [PluginShortcutDescriptor]
    let requiredPermissions: Set<PermissionKind>
}

@MainActor protocol QingniaoPlugin: AnyObject {
    var manifest: PluginManifest { get }
    func start() async throws
    func stop() async
}

protocol PluginEnablementStore {
    func isEnabled(_ id: PluginID, default defaultValue: Bool) -> Bool
    func setEnabled(_ enabled: Bool, for id: PluginID)
}

struct UserDefaultsPluginEnablementStore: PluginEnablementStore {
    init(defaults: UserDefaults = .standard)
    func isEnabled(_ id: PluginID, default defaultValue: Bool) -> Bool
    func setEnabled(_ enabled: Bool, for id: PluginID)
}

@MainActor final class PluginRegistry {
    init(enablementStore: PluginEnablementStore = UserDefaultsPluginEnablementStore())
    func register(_ plugin: any QingniaoPlugin) throws
    func startAll() async
    func stopAll() async
    func setEnabled(_ enabled: Bool, for id: PluginID) async throws
    func execute(_ actionID: PluginActionID) async throws
    var searchSources: [any SearchSource] { get }
    var settingsPages: [PluginSettingsPageDescriptor] { get }
}
```

`PluginMenuItemDescriptor` 包含 `id`、`titleKey`、`systemImageName`、`order`、`actionID`；`PluginShortcutDescriptor` 包含 `KeyboardShortcuts.Name` 与 `actionID`。`UserDefaultsPluginEnablementStore` 使用 `plugin.<plugin-id>.enabled` 保存启用状态；`PluginRegistry.setEnabled(_:for:)` 负责启动或停止插件并刷新全部贡献。

## 步骤

- [ ] 新建 `PluginRegistryTests`，先写重复 ID 与设置页排序失败测试：

```swift
let registry = PluginRegistry()
try registry.register(TestPlugin(id: PluginID(rawValue: "one"), settingsOrder: 20))
try registry.register(TestPlugin(id: PluginID(rawValue: "two"), settingsOrder: 10))
XCTAssertEqual(registry.settingsPages.map(\.order), [10, 20])
XCTAssertThrowsError(try registry.register(TestPlugin(id: PluginID(rawValue: "one"), settingsOrder: 30)))
```

同文件定义 `TestPlugin: QingniaoPlugin`，并补充重复动作 ID、启动失败隔离和停用清理断言。
- [ ] 运行：

```bash
xcodebuild test -project Qingniao.xcodeproj -scheme Qingniao -only-testing:QingniaoTests/PluginRegistryTests
```

预期：编译失败，提示 `PluginRegistry` 未定义。

- [ ] 实现上述类型和 `PluginRegistry.register(_:)`、`startAll()`、`stopAll()`、`setEnabled(_:for:)`、`execute(_:)`、`searchSources`、`settingsPages`、`menuItems`、`shortcuts`。
- [ ] 在 `AppContainer` 创建空注册表，但继续保留现有硬编码功能接线，确保用户行为不变。
- [ ] 写 ADR，明确插件为编译期第一方模块、同进程运行、随应用签名发布，以及未来改变模型必须重新评审权限和隔离。
- [ ] 将新增文件加入 App 与 Tests target，重新运行定向测试，预期 PASS。
- [ ] 运行 `./scripts/bump-version.sh --bump`、`plutil -lint Qingniao/Info.plist`，核对两处 Xcode 版本字段。
- [ ] 运行 `git diff --check` 后提交：`feat(plugin): add first-party plugin registry`。
