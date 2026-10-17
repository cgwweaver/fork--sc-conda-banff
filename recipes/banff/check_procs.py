# banff only warns when a procedure's shared library is missing, so check
# explicitly that all C procedures are loaded, in both message languages.
import banff
from banff.proc import BanffProcedure

procs = BanffProcedure.__subclasses__()
assert len(procs) == 9, [p.__name__ for p in procs]

for lang in (banff.SupportedLanguage.fr, banff.SupportedLanguage.en):
    banff.set_language(lang)
    not_loaded = [p.__name__ for p in procs if p._cproc_func is None]
    assert not not_loaded, (lang, not_loaded)
    print(f"{lang}: all {len(procs)} procedures loaded")
