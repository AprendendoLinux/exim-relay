#!/usr/bin/env python3
import sys
import email
import email.header
import email.utils
import os
import datetime
import re
import tempfile
import fcntl  # Para lock de arquivo simples

# Diretório de logs (mesmo usado pelo Exim)
LOG_DIR = "/var/log/exim4"
LOG_FILE = os.path.join(LOG_DIR, "full_subjects.log")
SEEN_IDS_FILE = os.path.join(LOG_DIR, ".seen_message_ids")  # Arquivo para deduplicação

IPV4_RE = re.compile(r'\b(\d{1,3}(?:\.\d{1,3}){3})\b')
# tenta extrair host a partir de "from <host> (" ou "from <host> "
HOST_FROM_RE = re.compile(r'from\s+([^\\s\\(\\;]+)', re.IGNORECASE)

def decode_subject(subject):
    """Decodifica o cabeçalho Subject, lidando com múltiplas partes codificadas."""
    decoded_parts = email.header.decode_header(subject)
    decoded_subject = ""
    for part, encoding in decoded_parts:
        if isinstance(part, bytes):
            decoded_subject += part.decode(encoding or 'utf-8', errors='replace')
        else:
            decoded_subject += part
    return decoded_subject.strip().replace('\n', ' ')

def parse_received_for_origin(msg):
    """
    Tenta extrair host e IP de origem a partir dos headers 'Received'.
    Usa o último Received (tipicamente o mais próximo da origem) e tenta regex.
    Retorna (host, ip) — ou (None, None) se não encontrar.
    """
    received_headers = msg.get_all('Received', [])
    if not received_headers:
        return None, None

    # normalmente a pilha de Received vai do mais recente ao mais antigo na ordem do cabeçalho
    # o remetente original costuma estar no último Received -> iteramos de trás pra frente
    for header in reversed(received_headers):
        # <header> = header.replace('\n', ' ')  # Evita quebras
        # procura IP
        ip_match = IPV4_RE.search(header)
        host_match = HOST_FROM_RE.search(header)
        ip = ip_match.group(1) if ip_match else None
        host = None
        if host_match:
            host_candidate = host_match.group(1).strip()
            # algumas vezes o campo 'from' vem com '[ip]' ou com parênteses; limpe caracteres extras
            host_candidate = host_candidate.strip('[];(),')
            # se host é um IP, ignore como host (vamos usar como ip)
            if IPV4_RE.match(host_candidate):
                # host candidate é ip — se ainda não temos ip, use
                if not ip:
                    ip = host_candidate
            else:
                host = host_candidate

        # se encontramos algo útil, retorne
        if host or ip:
            return host, ip

    return None, None

def get_env_origin():
    """
    Tenta extrair host/ip de variáveis de ambiente comuns que Exim/pipes costumam
    disponibilizar quando executam filtros.
    """
    env_vars_host = [
        'SENDER_HOST_NAME', 'SENDER_HOST', 'SENDER_HOSTNAME', 'SENDER_HOST_ADDR',
        'SENDER_HOST_ADDRESS', 'SENDER_HOST_IPV4', 'REMOTE_HOST', 'CLIENT_HOST',
        'EXIM_SENDER_HOST', 'EXIM_HOST'
    ]
    env_vars_ip = [
        'SENDER_IP', 'SENDER_HOST_ADDRESS', 'REMOTE_ADDR', 'REMOTE_HOST_ADDR',
        'CLIENT_ADDRESS', 'CLIENT_IP', 'EXIM_REMOTE_IP'
    ]

    host = None
    ip = None

    for v in env_vars_host:
        val = os.environ.get(v)
        if val:
            host = val.strip().replace('\n', ' ')
            break

    for v in env_vars_ip:
        val = os.environ.get(v)
        if val:
            # normalize: pode vir com colchetes
            ip_match = IPV4_RE.search(val)
            if ip_match:
                ip = ip_match.group(1)
            else:
                ip = val.strip().replace('\n', ' ')
            break

    return host, ip

def is_already_logged(message_id):
    """Verifica e marca ID como visto usando lock de arquivo para evitar duplicatas."""
    if not message_id or message_id == '[Sem ID]':
        return False

    try:
        with open(SEEN_IDS_FILE, 'a+') as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)  # Lock exclusivo
            f.seek(0)
            seen_ids = f.read().splitlines()
            if message_id in seen_ids:
                return True
            f.write(message_id + '\n')
            return False
    except Exception as e:
        # Falha no lock: logar de qualquer forma, mas avisar
        print(f"Erro no dedup: {e}", file=sys.stderr)
        return False

def main():
    # Obter o ID da mensagem cedo para dedup
    message_id = os.environ.get('MESSAGE_EXIM_ID', '[Sem ID]')
    if is_already_logged(message_id):
        print(f"Duplicata ignorada para {message_id}", file=sys.stderr)
        return  # Sai sem logar novamente

    # Ler o e-mailมีความ da entrada padrão
    msg = email.message_from_file(sys.stdin)

    # Extrair o Subject completo
    subject = msg.get('Subject', '[Sem Assunto]')
    decoded_subject = decode_subject(subject)

    # Extrair outras infos úteis para o log
    date = msg.get('Date', datetime.datetime.now().isoformat()).replace('\n', ' ')
    from_addr = msg.get('From', '[Desconhecido]').replace('\n', ' ')

    # Extrair todos os endereços de To e Cc usando getaddresses para parse correto
    to_headers = msg.get_all('To', []) + msg.get_all('Cc', [])
    all_to_addrs = []
    for header in to_headers:
        # Parseia nomes e emails, pega apenas emails
        parsed = email.utils.getaddresses([header])
        all_to_addrs.extend([email for name, email in parsed if email])
    if all_to_addrs:
        to_addr = ', '.join(all_to_addrs)
    else:
        to_addr = '[Desconhecido]'
    to_addr = to_addr.replace('\n', ' ').strip()

    # Tentar extrair origin host/ip do header Received
    origin_host, origin_ip = parse_received_for_origin(msg)

    # Se não encontrou nos Received, tentar variáveis de ambiente
    if not origin_host and not origin_ip:
        env_host, env_ip = get_env_origin()
        if env_host and not origin_host:
            origin_host = env_host
        if env_ip and not origin_ip:
            origin_ip = env_ip

    # Último fallback: marcar como desconhecido
    origin_host = origin_host or '[Desconhecido]'
    origin_ip = origin_ip or '[Desconhecido]'

    # Formatar a linha de log (garante single-line)
    log_line = (
        f"Message-ID: {message_id} | Date: {date} | From: {from_addr} | To: {to_addr} | "
        f"Origin-Host: {origin_host} | Origin-IP: {origin_ip} | Subject: {decoded_subject}\n"
    )

    # Salvar no log (append)
    try:
        # garante que o diretório existe
        os.makedirs(LOG_DIR, exist_ok=True)
        with open(LOG_FILE, 'a') as f:
            f.write(log_line)
    except Exception as e:
        # se falhar, emitir no stderr
        print(f"ERRO ao escrever log: {e}", file=sys.stderr)
        print(log_line, file=sys.stderr)

if __name__ == "__main__":
    main()