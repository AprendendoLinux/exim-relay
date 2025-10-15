#!/usr/bin/env python3
import sys
import email
import email.header
import os
import datetime

# Diretório de logs (mesmo usado pelo Exim)
LOG_DIR = "/var/log/exim4"
LOG_FILE = os.path.join(LOG_DIR, "full_subjects.log")

def decode_subject(subject):
    """Decodifica o cabeçalho Subject, lidando com múltiplas partes codificadas."""
    decoded_parts = email.header.decode_header(subject)
    decoded_subject = ""
    for part, encoding in decoded_parts:
        if isinstance(part, bytes):
            decoded_subject += part.decode(encoding or 'utf-8', errors='replace')
        else:
            decoded_subject += part
    return decoded_subject.strip()

def main():
    # Ler o e-mail da entrada padrão
    msg = email.message_from_file(sys.stdin)
    
    # Extrair o Subject completo
    subject = msg.get('Subject', '[Sem Assunto]')
    decoded_subject = decode_subject(subject)
    
    # Extrair outras infos úteis para o log
    date = msg.get('Date', datetime.datetime.now().isoformat())
    from_addr = msg.get('From', '[Desconhecido]')
    to_addr = msg.get('To', '[Desconhecido]')
    
    # Obter o ID da mensagem do Exim (disponível via variável de ambiente)
    message_id = os.environ.get('MESSAGE_EXIM_ID', '[Sem ID]')
    
    # Formatar a linha de log com o ID da mensagem
    log_line = f"Message-ID: {message_id} | Date: {date} | From: {from_addr} | To: {to_addr} | Subject: {decoded_subject}\n"
    
    # Salvar no log
    with open(LOG_FILE, 'a') as f:
        f.write(log_line)

if __name__ == "__main__":
    main()
