for i in $(seq 1 5); do                                                                        
  echo "{\"id\":$((300+i)),\"event_type\":\"nifi_jdbc\",\"city\":\"Chicago\",\"created_at\":\"$(date -u +'%Y-%m-%d %H:%M:%S')\"}" | \
    docker exec -i redpanda rpk topic produce raw-events
done