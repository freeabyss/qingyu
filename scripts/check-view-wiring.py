#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""视图接线门禁：同一文件内定义的 SwiftUI View，必须至少被引用一次。

背景：v1.2.0「合并为五页」重构把 BlacklistManagementSection 从设置页里掉了出去，
但结构体与后端一直保留——功能齐备却没有入口，用户无法管理搜索黑名单（违反 PRD FR-SEARCH-8i）。
这类「定义还在、入口没了」的缺陷编译器不报、测试不报，只有人肉核对界面清单才发现。

这里对每个源文件做最简单的自引用检查：文件内的 `struct X: View`，若在整个文件里
只出现一次（仅定义行），说明它没被任何地方使用——除非它要被外部文件使用。
为降低误报，只检查设计上「本就应在同文件被使用的私有 section 组件」：
限定文件名以 View.swift / SettingsView.swift 结尾，且结构体名含 Section / Row / Sheet / Pane。
"""
import re
import sys
from pathlib import Path

ROOT = Path('Qingyu')
SUFFIX_HINT = re.compile(r'(Section|Row|Sheet|Pane|Badge|Card)$')

def check_file(path: Path) -> list:
    src = path.read_text(encoding='utf-8')
    problems = []
    for m in re.finditer(r'struct (\w+)\s*:\s*View', src):
        name = m.group(1)
        if not SUFFIX_HINT.search(name):
            continue
        # 统计整个仓库里对该名字的引用（排除本文件的定义）
        problems.append(name)  # placeholder, resolved below
    return problems

def main():
    # 收集全仓所有 swift 文本，统计名字出现次数
    texts = {p: p.read_text(encoding='utf-8') for p in ROOT.rglob('*.swift')}
    offenders = []
    for p, src in texts.items():
        for m in re.finditer(r'struct (\w+)\s*:\s*View', src):
            name = m.group(1)
            if not SUFFIX_HINT.search(name):
                continue
            total = sum(len(re.findall(r'\b' + re.escape(name) + r'\b', t)) for t in texts.values())
            # 全仓只出现 1 次 = 仅定义，没人用
            if total <= 1:
                offenders.append((name, str(p)))

    if offenders:
        print('    FAILED：以下 View 结构体定义后从未被引用（疑似入口丢失 / 死代码）')
        for name, path in offenders:
            print(f'      {name}  @  {path}')
        sys.exit(1)

    print('    OK')

main()