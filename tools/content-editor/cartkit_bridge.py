"""Run the linked cart authoring tool with the editor's supported game bases."""
import importlib.util
import sys


def main(argv):
    if not argv:
        raise SystemExit("Missing linked cartkit path")
    spec = importlib.util.spec_from_file_location("linked_cartkit", argv[0])
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    module.BASES = tuple(dict.fromkeys((*module.BASES, "firered")))
    return module.main(argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
