"""Collect notices for the Python distributions used by the frozen backend."""
import ast
import importlib_metadata as metadata
from pathlib import Path
import shutil
import sys
import urllib.request

root = Path(__file__).resolve().parents[1]
destination = Path(sys.argv[1])
destination.mkdir(parents=True, exist_ok=True)
toc = ast.literal_eval(Path(sys.argv[2]).read_text())
modules = {row[0].split('.')[0] for row in toc[1]}
distributions = {name for module, names in metadata.packages_distributions().items() if module in modules for name in names}
distributions.add('pyinstaller')
for name in sorted(distributions):
    dist = metadata.distribution(name)
    folder = destination/(dist.metadata['Name']+'-'+dist.version)
    folder.mkdir(exist_ok=True)
    (folder/'METADATA.txt').write_text(str(dist.metadata), encoding='utf-8')
    for file in dist.files or []:
        if any(word in file.name.casefold() for word in ('license', 'licence', 'copying', 'notice', 'copyright')) and dist.locate_file(file).is_file():
            shutil.copy2(dist.locate_file(file), folder/file.name)
urllib.request.urlretrieve('https://raw.githubusercontent.com/python/cpython/v3.9.6/LICENSE', destination/'Python-3.9.6-LICENSE.txt')
