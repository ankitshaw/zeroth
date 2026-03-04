#!/bin/bash
# ============================================================
# Zeroth — Produce 100,000 events to Redpanda
# ============================================================
# Sends JSON events to the 'raw-events' topic.
# NiFi (ConsumeKafka → PutDatabaseRecord) picks them up
# and writes to iceberg.demo.events via Trino JDBC.
#
# Usage:
#   chmod +x examples/produce-100k.sh
#   ./examples/produce-100k.sh
#
# To monitor progress:
#   docker exec redpanda rpk topic describe raw-events
# ============================================================

set -euo pipefail

TOPIC="raw-events"
TOTAL=100000
BATCH_SIZE=5
CONTAINER="redpanda"

# --- Data pools for realistic variety ---
EVENT_TYPES=("page_view" "click" "purchase" "signup" "logout" "search" "add_to_cart" "remove_from_cart" "checkout" "review" "share" "bookmark" "login" "scroll" "hover" "download" "upload" "comment" "like" "subscribe")
CITIES=("New York" "London" "Tokyo" "Berlin" "Paris" "Sydney" "Mumbai" "Toronto" "Dubai" "Singapore" "São Paulo" "Seoul" "Amsterdam" "Stockholm" "Barcelona" "Chicago" "San Francisco" "Austin" "Denver" "Seattle")
DEVICES=("mobile" "desktop" "tablet")
BROWSERS=("Chrome" "Safari" "Firefox" "Edge")
OS_LIST=("iOS" "Android" "Windows" "macOS" "Linux")
REFERRERS=("google" "direct" "twitter" "facebook" "linkedin" "email" "reddit" "bing" "youtube" "instagram")
PAGES=("/home" "/products" "/products/123" "/cart" "/checkout" "/profile" "/settings" "/search" "/about" "/blog" "/blog/post-1" "/pricing" "/docs" "/api" "/contact")

echo "============================================"
echo "  Zeroth — Producing ${TOTAL} events"
echo "  Topic: ${TOPIC}"
echo "  Batch size: ${BATCH_SIZE}"
echo "============================================"

# Create topic if it doesn't exist
docker exec ${CONTAINER} rpk topic create ${TOPIC} --partitions 3 2>/dev/null || true

SENT=0
START_TIME=$(date +%s)

while [ $SENT -lt $TOTAL ]; do
    # Build a batch of JSON messages
    BATCH=""
    for i in $(seq 1 $BATCH_SIZE); do
        if [ $SENT -ge $TOTAL ]; then break; fi
        
        SENT=$((SENT + 1))
        
        # Random selections
        EVENT_TYPE=${EVENT_TYPES[$((RANDOM % ${#EVENT_TYPES[@]}))]}
        CITY=${CITIES[$((RANDOM % ${#CITIES[@]}))]}
        DEVICE=${DEVICES[$((RANDOM % ${#DEVICES[@]}))]}
        BROWSER=${BROWSERS[$((RANDOM % ${#BROWSERS[@]}))]}
        OS=${OS_LIST[$((RANDOM % ${#OS_LIST[@]}))]}
        REFERRER=${REFERRERS[$((RANDOM % ${#REFERRERS[@]}))]}
        PAGE=${PAGES[$((RANDOM % ${#PAGES[@]}))]}
        
        USER_ID=$((RANDOM % 5000 + 1))
        SESSION_DURATION=$((RANDOM % 3600))
        AMOUNT=$(printf "%.2f" "$(echo "scale=2; $((RANDOM % 50000)) / 100" | bc)")
        
        # Timestamp: random within the last 30 days
        DAYS_AGO=$((RANDOM % 30))
        HOURS=$((RANDOM % 24))
        MINS=$((RANDOM % 60))
        SECS=$((RANDOM % 60))
        TS=$(date -u -v-${DAYS_AGO}d -v${HOURS}H -v${MINS}M -v${SECS}S +'%Y-%m-%d %H:%M:%S' 2>/dev/null || \
             date -u -d "-${DAYS_AGO} days +${HOURS} hours +${MINS} minutes +${SECS} seconds" +'%Y-%m-%d %H:%M:%S' 2>/dev/null)

        # Build payload as pipe-delimited string (avoids nested JSON quote issues)
        PAYLOAD="${DEVICE}|${BROWSER}|${OS}|${REFERRER}|${PAGE}|${SESSION_DURATION}|${AMOUNT}"
        
        RECORD="{\"id\":${SENT},\"event_type\":\"${EVENT_TYPE}\",\"user_id\":${USER_ID},\"payload\":\"${PAYLOAD}\",\"city\":\"${CITY}\",\"created_at\":\"${TS}\"}"
        
        BATCH="${BATCH}${RECORD}\n"
    done
    
    # Send batch to Redpanda
    echo -e "$BATCH" | docker exec -i ${CONTAINER} rpk topic produce ${TOPIC} > /dev/null 2>&1
    
    # Progress
    ELAPSED=$(( $(date +%s) - START_TIME ))
    RATE=$( [ $ELAPSED -gt 0 ] && echo "$((SENT / ELAPSED))" || echo "∞" )
    printf "\r  ⚡ Produced: %d / %d  |  %s events/sec  |  %ds elapsed" $SENT $TOTAL "$RATE" $ELAPSED
done

END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))

echo ""
echo "============================================"
echo "  ✅ Done! ${TOTAL} events produced"
echo "  ⏱  Total time: ${TOTAL_TIME}s"
echo "  📊 Rate: $((TOTAL / (TOTAL_TIME > 0 ? TOTAL_TIME : 1))) events/sec"
echo "============================================"
echo ""
echo "  Verify in Redpanda:"
echo "    docker exec redpanda rpk topic describe ${TOPIC}"
echo ""
echo "  Verify in Trino (after NiFi processes):"
echo "    docker exec trino trino --execute \"SELECT count(*) FROM iceberg.demo.events\""
echo ""
