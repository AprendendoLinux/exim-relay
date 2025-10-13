#!/usr/bin/env python3
import sys
import re
import base64
import quopri
import os

DECODE_DEBUG = os.environ.get("DECODE_DEBUG", "").lower() in ("1", "yes", "true")

def debug(*args):
    if DECODE_DEBUG:
        print(*args, file=sys.stderr)

pattern = re.compile(r'^(.*?\s+\S+\s+<=.*?T=")(.*?)"(.*)$', re.IGNORECASE)
encoded_word_re = re.compile(r"=\?([^?]+)\?([QBqb])\?(.+?)\?=", re.DOTALL)
octal_escape_re = re.compile(r'\\([0-7]{3})\\([0-7]{3})|\\([0-7]{1,3})')

def decode_q(text, charset):
    try:
        b = quopri.decodestring(text.replace("_", " "))
        return b.decode(charset or "utf-8", errors="replace")
    except Exception as e:
        debug(f"Erro em decode_q: {e}")
        return text

def decode_b(text, charset):
    try:
        b = base64.b64decode(text)
        return b.decode(charset or "utf-8", errors="replace")
    except Exception as e:
        debug(f"Erro em decode_b: {e}")
        return text

def decode_octal(text):
    def octal_to_char(match):
        try:
            if match.group(1) and match.group(2):
                byte1 = int(match.group(1), 8)
                byte2 = int(match.group(2), 8)
                return bytes([byte1, byte2]).decode('utf-8', errors='replace')
            elif match.group(3):
                return chr(int(match.group(3), 8))
        except Exception as e:
            debug(f"Erro em decode_octal: {e}")
            return match.group(0)
    return octal_escape_re.sub(octal_to_char, text)

def decode_subject(encoded):
    original = encoded
    debug(f"Input original: {original}")

    cleaned = re.sub(r'=\,?$', '', original)
    debug(f"Cleaned input: {cleaned}")

    decoded = decode_octal(cleaned)
    decoded = re.sub(r"\?=\s*=\?", "?==?", decoded)

    out = []
    last_end = 0
    last_charset = last_enc = None
    last_ended_alnum = False
    debug_tokens = []

    for m in encoded_word_re.finditer(decoded):
        start, end = m.span()
        charset, enc_type, data = m.groups()
        enc_type = enc_type.upper()

        pre = decoded[last_end:start]
        if pre:
            if pre.isspace() and last_charset and charset == last_charset and last_enc == enc_type:
                if last_ended_alnum:
                    pass
                else:
                    out.append(pre)
            else:
                out.append(pre)

        if enc_type == "Q":
            part = decode_q(data, charset)
        else:
            part = decode_b(data, charset)

        debug_tokens.append((m.group(0), charset, enc_type, part))

        if out and last_ended_alnum and part and re.match(r"^[A-Za-z0-9À-ÿ]", part):
            out[-1] = out[-1] + part
        else:
            out.append(part)

        last_end = end
        last_charset = charset
        last_enc = enc_type
        last_ended_alnum = bool(part and re.search(r"[A-Za-z0-9À-ÿ]$", part))

    tail = decoded[last_end:]
    if tail:
        out.append(tail)

    decoded = "".join(out)

    decoded = decoded.replace("??=", "").replace("=?=", "")
    # 🔧 Correção: tratar '\n' literal sem afetar quebras reais
    decoded = decoded.replace("\\n", " ")
    decoded = re.sub(r"\s{2,}", " ", decoded).strip()

    if DECODE_DEBUG:
        debug("----- DECODE DEBUG START -----")
        debug("Encoded original:", original)
        debug("Cleaned input:", cleaned)
        debug("After octal decode:", decoded)
        for tok, cs, et, dec in debug_tokens:
            preview = dec if len(dec) < 120 else dec[:120] + "..."
            debug(f"[token] {cs} {et} -> {preview}")
        debug("Decoded final:", decoded)
        debug("------ DECODE DEBUG END ------")

    return decoded

def main():
    debug("Starting decode_log.py")
    try:
        for line in sys.stdin:
            debug(f"Received line: {line.strip()}")
            try:
                match = pattern.search(line)
                if match:
                    prefix, subject_enc, suffix = match.groups()
                    debug(f"Captured subject: {subject_enc}")
                    subject_dec = decode_subject(subject_enc)
                    debug(f"Decoded subject: {subject_dec}")
                    sys.stdout.write(f"{prefix}{subject_dec}{suffix}\n")
                else:
                    debug("No Subject match in line")
                    sys.stdout.write(line)
            except Exception as e:
                debug(f"Error processing line: {e}")
                sys.stdout.write(line)
            sys.stdout.flush()
    except Exception as e:
        debug(f"Fatal error in decode_log.py: {e}")
        raise

if __name__ == "__main__":
    print("decode_log.py iniciado", file=sys.stderr)
    main()
