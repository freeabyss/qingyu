#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""本地化一致性门禁。

背景：连续几轮里出现过三类真实的本地化缺陷，都是靠「换语言截图」才发现的，
而当时 verify.sh 只校验了 xcstrings 的 JSON 是否合法：
  1. 遗留旧产品名（Assistant）——文案层问题，与语言无关
  2. 某个键的所有语言都被写成中文（包括 en / fr）——批量改写脚本越界
  3. 单位分类标签写成「Temperature 温度」——同一概念的两种语言并排

这里把能机器判定、且不产生误报的检查变成硬门禁：
  A. 声明了本地化的键，五种语言必须齐全（en / zh-Hans / zh-Hant / ja / fr）
  B. en / fr 的值里不得出现中文字符（品牌名「清羽」除外）
  C. 同一概念的中英文并排（只覆盖实际出现过的分类词，避免误报）
"""
import json
import re
import sys

PATH = 'Qingyu/Resources/Localizable.xcstrings'
LANGUAGES = ['en', 'zh-Hans', 'zh-Hant', 'ja', 'fr']
CJK = re.compile(r'[\u4e00-\u9fff]')
# 允许出现在 en / fr 里的中文字符：产品中文名
ALLOWED_CJK_IN_LATIN = ('清羽',)

# 「同一概念的中英并排」。技术名词（Enter / Esc / OCR / macOS / URL / App /
# RTF / Finder / ID / SwiftUI / GRDB）后跟动词或量词属正常混排，不在其列；
# 这里只抓「英文分类词 + 空格 + 该词的中文译名」这种真正的重复表达。
CONCAT_PATTERNS = [
    (re.compile(r'\b(Temperature|Duration|Length|Mass|Volume)\s+[\u4e00-\u9fff]{1,3}$'),
     '分类词中英并排'),
]

def value_of(entry, lang):
    unit = entry.get('localizations', {}).get(lang, {}).get('stringUnit', {})
    return unit.get('value') or ''

def main():
    data = json.load(open(PATH, encoding='utf-8'))
    strings = data.get('strings', {})
    problems = []

    for key, entry in strings.items():
        localizations = entry.get('localizations') or {}
        if not localizations:
            continue

        values = {lang: value_of(entry, lang) for lang in LANGUAGES}

        # A. 语言齐全（全空的是界面样例值，不参与）
        # 纯格式串（只含 %@ / %lld / 分隔符，没有文字）缺语言不影响显示，同样豁免。
        def is_format_only(text):
            if not text:
                return False
            # 精确匹配 printf 占位符：%1$lld / %@ / %d / %.1f / %% 等，
            # 不能只吃掉一个字符，否则 %1$lld 会残留 "ld" 被当成文字。
            without_placeholders = re.sub(
                r'%(?:\d+\$)?(?:lld|ld|d|u|f|\.\d+f|@|x|X|%)', '', text
            )
            # 尺寸/单位符号不算文字：x（乘号）、px、pt
            without_placeholders = re.sub(r'\b(px|pt)\b|x', '', without_placeholders)
            return not re.search(r'[A-Za-z\u4e00-\u9fff\u3040-\u30ff]', without_placeholders)

        # 有内容的语言全部「去掉占位符后没有文字」→ 这条本来就是纯格式串，豁免。
        present = [v for v in values.values() if v]
        format_only = bool(present) and all(is_format_only(v) for v in present)
        if any(values.values()) and not format_only:
            missing = [lang for lang in LANGUAGES if not values[lang]]
            if missing:
                problems.append('缺少语言 %s：%s' % (missing, key))
                continue

        # B. en / fr 不得含中文（品牌名除外）
        for lang in ('en', 'fr'):
            stripped = values[lang]
            for allowed in ALLOWED_CJK_IN_LATIN:
                stripped = stripped.replace(allowed, '')
            if CJK.search(stripped):
                problems.append('%s 出现中文：%s => %r' % (lang, key, values[lang]))

        # C. 同一概念中英并排
        for lang, value in values.items():
            for pattern, label in CONCAT_PATTERNS:
                if pattern.search(value.strip()):
                    problems.append('%s（%s）：%s => %r' % (label, lang, key, value))

    if problems:
        print('    FAILED：本地化一致性检查未通过')
        for problem in problems:
            print('      ' + problem)
        sys.exit(1)

    print('    OK（%d 条）' % len(strings))

main()