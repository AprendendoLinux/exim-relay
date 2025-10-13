#!/bin/bash
set -e
[ "${DEBUG}" == "yes" ] && echo "Debug mode enabled"

# Timezone
if [ -n "${TZ}" ]; then
  echo "Configuring timezone to ${TZ}"
  ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime
  echo "${TZ}" > /etc/timezone
else
  echo "TZ not set, using UTC"
fi

# Credenciais
if [ -n "${SMTP_PASSWORD_FILE}" ] && [ -e "${SMTP_PASSWORD_FILE}" ]; then
  SMTP_PASSWORD=$(cat "${SMTP_PASSWORD_FILE}")
fi
if [ -n "${SMTP_USERNAME_FILE}" ] && [ -e "${SMTP_USERNAME_FILE}" ]; then
  SMTP_USERNAME=$(cat "${SMTP_USERNAME_FILE}")
fi

: "${SMTP_SERVER:?Environment variable SMTP_SERVER is required}"
: "${SERVER_HOSTNAME:?Environment variable SERVER_HOSTNAME is required}"
SMTP_PORT="${SMTP_PORT:-587}"
RELAY_NETS="${RELAY_NETS:-172.16.0.0/12}"

# Configuração do Exim usando o mecanismo Debian
mkdir -p /etc/exim4
cat > /etc/exim4/update-exim4.conf.conf <<EOF
dc_eximconfig_configtype='smarthost'
dc_other_hostnames=''
dc_local_interfaces=''
dc_readhost='${SERVER_HOSTNAME}'
dc_relay_domains=''
dc_minimaldns='false'
dc_relay_nets='${RELAY_NETS}'
dc_smarthost='${SMTP_SERVER}::${SMTP_PORT}'
CFILEMODE='644'
dc_use_split_config='false'
dc_hide_mailname='true'
dc_mailname_in_oh='true'
dc_localdelivery='mail_spool'
EOF

# Configurar /etc/mailname
echo "${SERVER_HOSTNAME}" > /etc/mailname

# Configurar autenticação para o smarthost
echo "${SMTP_SERVER}:${SMTP_USERNAME}:${SMTP_PASSWORD}" > /etc/exim4/passwd.client
chmod 640 /etc/exim4/passwd.client

# Definir log_selector de forma segura, anexando aos seletores existentes
if [ -f /etc/exim4/exim4.conf.template ]; then
  if grep -q "^log_selector" /etc/exim4/exim4.conf.template; then
    sed -i '/^log_selector/s/$/ +subject +smtp_protocol_error +smtp_syntax_error/' /etc/exim4/exim4.conf.template
  else
    echo "log_selector = +subject +smtp_protocol_error +smtp_syntax_error" >> /etc/exim4/exim4.conf.template
  fi
fi

# Gerar configuração do Exim
update-exim4.conf --verbose

echo "Exim configuration generated"

# Logs
mkdir -p /var/log/exim4
touch /var/log/exim4/mainlog /var/log/exim4/paniclog /var/log/exim4/rejectlog /var/log/exim4/mail.log
chmod 777 /var/log/exim4
chmod 666 /var/log/exim4/*

# Execução
if [ "${DECODE_SUBJECT}" == "yes" ]; then
  echo "🧩 DECODE_SUBJECT=yes → piping Exim log through decode_log.py"
  # Verificar se o decode_log.py existe e é executável
  if [ ! -f /decode_log.py ]; then
    echo "Erro: /decode_log.py não encontrado" >&2
    exit 1
  fi
  if [ ! -x /decode_log.py ]; then
    chmod +x /decode_log.py
  fi
  # Iniciar Exim em background
  stdbuf -oL /usr/sbin/exim4 -bd -q30m &
  EXIM_PID=$!
  echo "Exim iniciado com PID $EXIM_PID"
  sleep 3
  # Iniciar pipeline em foreground, salvando em mail.log e mantendo no stdout
  echo "Iniciando pipeline para decode_log.py"
  exec stdbuf -oL tail -F /var/log/exim4/mainlog | stdbuf -i0 -o0 python3 /decode_log.py 2> /var/log/exim4/decode_errors.log | tee /var/log/exim4/mail.log
else
  echo "🚀 Starting Exim (heavy build, Subject decoded natively)"
  exec stdbuf -oL /usr/sbin/exim4 -bdf -q30m
fi
