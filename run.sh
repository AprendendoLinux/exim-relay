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

: "${SERVER_HOSTNAME:?Environment variable SERVER_HOSTNAME is required}"
SMTP_PORT="${SMTP_PORT:-25}"
RELAY_NETS="${RELAY_NETS:-172.16.0.0/12}"

# Configuração do Exim usando o mecanismo Debian
mkdir -p /etc/exim4
if [ -n "${SMTP_SERVER}" ]; then
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
else
  cat > /etc/exim4/update-exim4.conf.conf <<EOF
dc_eximconfig_configtype='internet'
dc_other_hostnames=''
dc_local_interfaces=''
dc_readhost='${SERVER_HOSTNAME}'
dc_relay_domains=''
dc_minimaldns='false'
dc_relay_nets='${RELAY_NETS}'
dc_smarthost=''
CFILEMODE='644'
dc_use_split_config='false'
dc_hide_mailname='true'
dc_mailname_in_oh='true'
dc_localdelivery='mail_spool'
EOF
fi

# Configurar /etc/mailname
echo "${SERVER_HOSTNAME}" > /etc/mailname

# Configurar autenticação para o smarthost (se fornecida)
if [ -n "${SMTP_SERVER}" ] && [ -n "${SMTP_USERNAME}" ] && [ -n "${SMTP_PASSWORD}" ]; then
  echo "${SMTP_SERVER}:${SMTP_USERNAME}:${SMTP_PASSWORD}" > /etc/exim4/passwd.client
  chmod 640 /etc/exim4/passwd.client
fi

# Configurar protocolo de rede (EXIM_INET_PROTOCOLS) apenas se não for relay autenticado
if [ -f /etc/exim4/exim4.conf.template ] && [ -z "${SMTP_SERVER}" ] || [ -z "${SMTP_USERNAME}" ] || [ -z "${SMTP_PASSWORD}" ]; then
  sed -i '/^disable_ipv6/d' /etc/exim4/exim4.conf.template
  if [ "${EXIM_INET_PROTOCOLS}" = "ipv4" ]; then
    sed -i '1i disable_ipv6 = true' /etc/exim4/exim4.conf.template
  fi
fi

# Definir log_selector de forma segura, anexando aos seletores existentes
if [ -f /etc/exim4/exim4.conf.template ]; then
  if grep -q "^log_selector" /etc/exim4/exim4.conf.template; then
    sed -i '/^log_selector/s/$/ +subject +smtp_protocol_error +smtp_syntax_error/' /etc/exim4/exim4.conf.template
  else
    echo "log_selector = +subject +smtp_protocol_error +smtp_syntax_error" >> /etc/exim4/exim4.conf.template
  fi
fi

# Adicionar router e transport para capturar assuntos completos
if [ -f /etc/exim4/exim4.conf.template ]; then
  if ! grep -q "^log_full_subject:" /etc/exim4/exim4.conf.template; then
    sed -i '/^begin routers$/a \
log_full_subject:\
  driver = accept\
  condition = ${if eq{$h_subject:}{} {0}{1}}\
  transport = log_subject_transport\
  no_verify\
  unseen' /etc/exim4/exim4.conf.template
  fi

  if ! grep -q "^log_subject_transport:" /etc/exim4/exim4.conf.template; then
    sed -i '/^begin transports$/a \
log_subject_transport:\
  driver = pipe\
  command = /usr/bin/python3 /log_subject.py\
  environment = MESSAGE_EXIM_ID=$message_exim_id\
  user = Debian-exim\
  group = Debian-exim' /etc/exim4/exim4.conf.template
  fi
fi

# Configuração para ALLOWED_SENDER_DOMAINS apenas se não for relay autenticado
if [ -n "${ALLOWED_SENDER_DOMAINS}" ] && [ -z "${SMTP_SERVER}" ] || [ -z "${SMTP_USERNAME}" ] || [ -z "${SMTP_PASSWORD}" ]; then
  echo "Configurando domínios permitidos para remetentes: ${ALLOWED_SENDER_DOMAINS}"
  mkdir -p /etc/exim4
  printf "%s\n" ${ALLOWED_SENDER_DOMAINS} > /etc/exim4/allowed_sender_domains

  # Remover configurações anteriores de ACL para evitar duplicatas
  sed -i '/^domainlist allowed_sender_domains/d; /^acl_check_sender:/,/^[^ ]/d; /^acl_smtp_mail/d' /etc/exim4/exim4.conf.template

  # Adicionar domainlist
  sed -i '/^begin acl$/i domainlist allowed_sender_domains = lsearch;/etc/exim4/allowed_sender_domains' /etc/exim4/exim4.conf.template

  # Adicionar ACL para checar sender domain com log de rejeição
  sed -i '/^begin acl$/a \
acl_check_sender:\
  deny\
    message = Unauthorized sender domain: $sender_address_domain\
    log_message = Rejected: Sender domain $sender_address_domain not in allowed_sender_domains\
    !condition = ${if exists {/etc/exim4/allowed_sender_domains}{${lookup{$sender_address_domain}lsearch{/etc/exim4/allowed_sender_domains}{yes}{no}}}{no}}\
  accept' /etc/exim4/exim4.conf.template

  # Adicionar acl_smtp_mail
  sed -i '/^begin acl$/i acl_smtp_mail = acl_check_sender' /etc/exim4/exim4.conf.template
fi

# Configuração para DKIM apenas se não for relay autenticado
if [ "${DKIM_AUTOGENERATE}" = "yes" ] && [ -n "${ALLOWED_SENDER_DOMAINS}" ] && [ -z "${SMTP_SERVER}" ] || [ -z "${SMTP_USERNAME}" ] || [ -z "${SMTP_PASSWORD}" ]; then
  echo "Gerando chaves DKIM automáticas para domínios permitidos"
  DKIM_SELECTOR="${DKIM_SELECTOR:-mail}"
  DKIM_KEY_DIR="/etc/opendkim/keys"
  mkdir -p "${DKIM_KEY_DIR}"
  for domain in ${ALLOWED_SENDER_DOMAINS}; do
    domain_dir="${DKIM_KEY_DIR}/${domain}"
    mkdir -p "${domain_dir}"
    if [ ! -f "${domain_dir}/${DKIM_SELECTOR}.private" ]; then
      opendkim-genkey -D "${domain_dir}" -d "${domain}" -s "${DKIM_SELECTOR}" -b 2048
      chown -R Debian-exim:Debian-exim "${domain_dir}"
      chmod 640 "${domain_dir}/${DKIM_SELECTOR}.private"
      echo "Chave DKIM gerada para ${domain}. Adicione ao DNS: $(cat "${domain_dir}/${DKIM_SELECTOR}.txt")"
    fi
  done
  # Criar arquivo de mapeamento para chaves DKIM
  > /etc/exim4/dkim_keys.conf
  for domain in ${ALLOWED_SENDER_DOMAINS}; do
    domain_key="${DKIM_KEY_DIR}/${domain}/${DKIM_SELECTOR}.private"
    if [ -f "${domain_key}" ]; then
      echo "${domain}:${domain_key}" >> /etc/exim4/dkim_keys.conf
    fi
  done
  chmod 640 /etc/exim4/dkim_keys.conf
  chown Debian-exim:Debian-exim /etc/exim4/dkim_keys.conf
fi

# Adicionar DKIM signing ao transport apenas se não for relay autenticado
if [ -f /etc/exim4/exim4.conf.template ] && [ -z "${SMTP_SERVER}" ] || [ -z "${SMTP_USERNAME}" ] || [ -z "${SMTP_PASSWORD}" ]; then
  transport_name=$([ -n "${SMTP_SERVER}" ] && echo "remote_smtp_smarthost" || echo "remote_smtp")
  # Garantir que o transporte exista
  if ! grep -q "^${transport_name}:" /etc/exim4/exim4.conf.template; then
    echo "${transport_name}:" >> /etc/exim4/exim4.conf.template
    echo "  driver = smtp" >> /etc/exim4/exim4.conf.template
  fi
  # Remover opções DKIM existentes para evitar duplicatas
  sed -i "/^${transport_name}:/,/^\S/ {/^  dkim_/d}" /etc/exim4/exim4.conf.template
  # Adicionar opções DKIM após o driver
  sed -i "/^${transport_name}:/,/^\S/ s#^\([ \t]*driver = smtp[ \t]*\$\)#\1\n  dkim_domain = \$sender_address_domain\n  dkim_selector = ${DKIM_SELECTOR:-mail}\n  dkim_private_key = \${lookup{\$sender_address_domain}lsearch{/etc/exim4/dkim_keys.conf}}\n  dkim_canon = relaxed\n  dkim_strict = false#" /etc/exim4/exim4.conf.template
fi

# Gerar configuração do Exim
update-exim4.conf --verbose

echo "Exim configuration generated"

# Logs
mkdir -p /var/log/exim4
touch /var/log/exim4/mainlog /var/log/exim4/paniclog /var/log/exim4/rejectlog /var/log/exim4/mail.log /var/log/exim4/full_subjects.log
chmod 777 /var/log/exim4
chmod 666 /var/log/exim4/*

# Execução
if [ "${DECODE_SUBJECT}" == "yes" ]; then
  echo "DECODE_SUBJECT=yes - piping Exim log through decode_log.py"
  if [ ! -f /decode_log.py ]; then
    echo "Erro: /decode_log.py não encontrado" >&2
    exit 1
  fi
  if [ ! -x /decode_log.py ]; then
    chmod +x /decode_log.py
  fi
  stdbuf -oL /usr/sbin/exim4 -bd -q30m &
  EXIM_PID=$!
  echo "Exim iniciado com PID $EXIM_PID"
  sleep 3
  echo "Iniciando pipeline para decode_log.py"
  exec stdbuf -oL tail -F /var/log/exim4/mainlog | stdbuf -i0 -o0 python3 /decode_log.py 2> /var/log/exim4/decode_errors.log | tee /var/log/exim4/mail.log
else
  echo "Starting Exim (heavy build, Subject decoded natively)"
  exec stdbuf -oL /usr/sbin/exim4 -bdf -q30m
fi
