#!/usr/bin/env python3
import sys
import re
import os

DECODE_DEBUG = os.environ.get("DECODE_DEBUG", "").lower() in ("1", "yes", "true")
FULL_SUBJECTS_LOG = "/var/log/exim4/full_subjects.log"

def debug(*args):
    if DECODE_DEBUG:
        print(*args, file=sys.stderr)

# Padrão para identificar linhas de entrega (contendo =>)
delivery_pattern = re.compile(r'\s+=>\s+')

def main():
    debug("Starting decode_log.py")
    try:
        for line in sys.stdin:
            debug(f"Received line: {line.strip()}")
            try:
                # Verificar se a linha é uma linha de entrega (contém =>)
                if delivery_pattern.search(line):
                    sys.stdout.write(line)
                else:
                    debug("Line skipped (not a delivery line)")
                sys.stdout.flush()
            except Exception as e:
                debug(f"Error processing line: {e}")
                # Em caso de erro, ignorar a linha para não interromper o pipeline
                continue
    except Exception as e:
        debug(f"Fatal error in decode_log.py: {e}")
        raise

if __name__ == "__main__":
    print("decode_log.py iniciado", file=sys.stderr)
    main()