#!/usr/bin/env bash
# Traffic generate karo taaki Grafana mein metrics dikhein
for i in $(seq 1 500); do curl -s http://localhost:8080/ > /dev/null; sleep 0.1; done
echo "done"
