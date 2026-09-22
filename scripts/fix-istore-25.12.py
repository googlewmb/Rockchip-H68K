#!/usr/bin/env python3
"""Apply narrowly scoped fixes after DIY2, before the first defconfig."""
from pathlib import Path
import re


def fix(root: Path) -> None:
    config = (root / '.config').read_text()

    # The small feed overrides Build/Compile and omits TARGET_CONFIGURE_OPTS.
    # tcping 0.5 otherwise invokes the host strip on the target ELF binary.
    tcping = root / 'feeds/small/tcping/Makefile'
    if tcping.exists():
        text = tcping.read_text()
        old = 'CC="$(TARGET_CC)" CFLAGS='
        new = 'CC="$(TARGET_CC)" STRIP="$(TARGET_CROSS)strip" CFLAGS='
        if old in text:
            tcping.write_text(text.replace(old, new))
            print('tcping: pass the target strip to the upstream makefile')
        elif new not in text:
            raise RuntimeError('tcping Build/Compile changed; review the strip fix')

    smartdns = root / 'package/myapp/smartdns/package/openwrt/Makefile'
    if smartdns.exists():
        text = smartdns.read_text()
        text = text.replace('https://www.github.com/', 'https://github.com/')
        call = '$(eval $(call Download,smartdns-webui))'
        guarded = 'ifdef CONFIG_PACKAGE_smartdns-ui\n' + call + '\nendif'
        if guarded not in text:
            if text.count(call) != 1:
                raise RuntimeError('SmartDNS WebUI download rule changed; review the fix')
            text = text.replace(call, guarded)
        smartdns.write_text(text)
        print('SmartDNS: download WebUI only when smartdns-ui is enabled')

    # This profile does not use fchomo. Do not rewrite its unknown dependency
    # graph or disable a package that a user explicitly selected.
    selected = re.search(
        r'^CONFIG_PACKAGE_(?:luci-app-fchomo|luci-i18n-fchomo-[^=]+)=[ym]$',
        config, re.M,
    )
    if not selected:
        for entry in (root / 'package/feeds').glob('*/luci-app-fchomo'):
            if not entry.is_symlink():
                raise RuntimeError(f'Refusing to remove a non-symlink: {entry}')
            entry.unlink()
            print(f'Exclude unused fchomo feed entry: {entry}')
    else:
        print('fchomo selected: keep it and let the strict defconfig check validate it')


if __name__ == '__main__':
    fix(Path.cwd())
