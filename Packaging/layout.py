"""Write Finder's native icon-view metadata without UI scripting."""
import pathlib, sys
from ds_store import DSStore
from mac_alias import Alias, Bookmark
root = pathlib.Path(sys.argv[1])
background = root / '.background' / 'background.tiff'
with DSStore.open(str(root / '.DS_Store'), 'w+') as store:
    store['.']['bwsp'] = {
        'ShowStatusBar': False, 'ShowTabView': False, 'ShowToolbar': False,
        'ShowPathbar': False, 'ShowSidebar': False, 'SidebarWidth': 0,
        'WindowBounds': '{{320, 100}, {500, 652}}', 'ContainerShowSidebar': False,
    }
    store['.']['icvp'] = {
        'viewOptionsVersion': 1, 'backgroundType': 2,
        'backgroundImageAlias': Alias.for_file(str(background)).to_bytes(),
        'iconSize': 112.0, 'textSize': 13.0, 'gridSpacing': 100.0,
        'gridOffsetX': 0.0, 'gridOffsetY': 0.0,
        'scrollPositionX': 0.0, 'scrollPositionY': 0.0,
        'backgroundColorRed': 1.0, 'backgroundColorGreen': 1.0, 'backgroundColorBlue': 1.0,
        'arrangeBy': 'none', 'labelOnBottom': True,
        'showItemInfo': False, 'showIconPreview': False,
    }
    store['.']['vSrn'] = ('long', 1)
    store['.']['icvl'] = ('type', b'icnv')
    store['.']['pBBk'] = Bookmark.for_file(str(background))
    store['Hidecell.app']['Iloc'] = (250, 175)
    store['Applications']['Iloc'] = (250, 420)
