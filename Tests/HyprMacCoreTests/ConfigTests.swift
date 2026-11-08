import Testing
@testable import HyprMacCore

struct ConfigTests {
    @Test func defaultConfigParsesCleanly() {
        let c = HyprConfig.parse(HyprConfig.defaultText)
        #expect(c.errors == [])
        #expect(c.binds.count > 30)
        let ws1 = c.binds.first { $0.dispatcher == "workspace" && $0.argument == "1" }
        #expect(ws1?.modifiers == [.option])
        #expect(ws1?.keyCode == 18)
        let special = c.binds.first { $0.dispatcher == "togglespecialworkspace" }
        #expect(special?.keyCode == 1) // S
    }

    @Test func variablesSectionsCommentsAndExecCommas() {
        let c = HyprConfig.parse("""
        $mod = SUPER   # command key
        general {
            gaps_in = 3
            gaps_out = 7
        }
        bind = $mod SHIFT, Q, exec, echo a,b ## not a comment
        bind = CTRL_ALT, left, movefocus, l
        """)
        #expect(c.errors == [])
        #expect(c.gapsIn == 3)
        #expect(c.gapsOut == 7)
        #expect(c.binds[0].modifiers == [.command, .shift])
        #expect(c.binds[0].argument == "echo a,b # not a comment")
        #expect(c.binds[1].modifiers == [.control, .option])
    }

    @Test func errors() {
        let c = HyprConfig.parse("""
        bind = HYPER, 1, workspace, 1
        bind = ALT, nokey, workspace, 1
        bind = ALT, 1, teleport, 1
        nonsense
        foo = bar
        """)
        #expect(c.errors.count == 5)
    }

    @Test func windowRules() {
        let c = HyprConfig.parse("""
        windowrule = workspace special, class:^(Slack|Messages)$
        windowrule = float, class:com\\.apple\\.calculator, title:Calc
        windowrule = workspace 3, class:Safari
        """)
        #expect(c.errors == [])
        #expect(c.rules[0].action == .workspace(specialWorkspaceID))
        #expect(c.rules[0].matches(appName: "slack", bundleID: nil, title: ""))
        #expect(!(c.rules[0].matches(appName: "Slacker", bundleID: nil, title: "")))
        #expect(c.rules[1].matches(appName: "Calculator", bundleID: "com.apple.calculator", title: "Calculator"))
        #expect(!(c.rules[1].matches(appName: "Calculator", bundleID: "com.apple.calculator", title: "Other")))
        #expect(c.rules[2].action == .workspace(3))
    }

    @Test func workspaceTarget() {
        #expect(WorkspaceTarget("3") == .number(3))
        #expect(WorkspaceTarget("special") == .special)
        #expect(WorkspaceTarget("special:chat") == .special)
        #expect(WorkspaceTarget("e+1") == .relative(1))
        #expect(WorkspaceTarget("e-1") == .relative(-1))
        #expect(WorkspaceTarget("previous") == .previous)
        #expect(WorkspaceTarget("abc") == nil)
    }
}
