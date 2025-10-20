FROM debian:bullseye-slim

RUN apt-get update && apt-get install -y \
  exim4 \
  python3 \
  python3-pip \
  opendkim-tools \
  && rm -rf /var/lib/apt/lists/*

COPY run.sh /run.sh
COPY decode_log.py /decode_log.py
COPY log_subject.py /log_subject.py

RUN chmod +x /run.sh /decode_log.py /log_subject.py

CMD ["/run.sh"]
