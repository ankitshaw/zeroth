import json
from datetime import datetime, timezone
import pyarrow as pa
from requests.sessions import Session
from pyiceberg.catalog import load_catalog

# --- THE REAL FIX (NETWORK INTERCEPTOR) ---
_original_request = Session.request

def patched_request(self, method, url, **kwargs):
    # BUG 1 FIX: PyIceberg hardcodes a request for temporary S3 credentials.
    # Polaris crashes because it doesn't have any to give for local MinIO.
    # Solution: Delete the header before the request is sent to the server.
    if "X-Iceberg-Access-Delegation" in self.headers:
        del self.headers["X-Iceberg-Access-Delegation"]
    
    if "headers" in kwargs and kwargs["headers"] and "X-Iceberg-Access-Delegation" in kwargs["headers"]:
        del kwargs["headers"]["X-Iceberg-Access-Delegation"]
        
    # Send the actual request
    response = _original_request(self, method, url, **kwargs)
    
    # BUG 2 FIX: Polaris returns "PUT" endpoints, crashing PyIceberg 3.14+
    # Solution: Scrub "PUT" from the response payload.
    if response.status_code == 200 and "/v1/config" in url:
        try:
            data = response.json()
            if "endpoints" in data:
                allowed = {"GET", "POST", "DELETE", "HEAD", "PATCH"}
                data["endpoints"] = [e for e in data["endpoints"] if e.split(" ")[0].upper() in allowed]
                response._content = json.dumps(data).encode('utf-8')
        except Exception:
            pass
            
    return response

# Apply the patch to all requests
Session.request = patched_request
# --- END NETWORK INTERCEPTOR ---

def run_ingest():
    catalog = load_catalog(
        "polaris",
        **{
            "uri": "http://localhost:8181/api/catalog",
            "credential": "root:polaris",
            "warehouse": "zeroth-warehouse",
            "scope": "PRINCIPAL_ROLE:ALL",
            
            # Local MinIO Credentials (used directly by PyArrow, skipping Polaris vending)
            "s3.endpoint": "http://localhost:9000",
            "s3.access-key-id": "admin",
            "s3.secret-access-key": "password123",
            "s3.path-style-access": "true",
            "s3.region": "us-east-1",
        },
    )

    print("📡 Loading table 'demo.events' from Polaris...")
    table = catalog.load_table("demo.events")

    data = [
        {
            "id": i,
            "event_type": "api_call",
            "city": "Harrison" if i % 2 == 0 else "Newark",
            "created_at": datetime.now(timezone.utc)
        }
        for i in range(100, 110)
    ]

    print("✍️ Appending 10 rows to MinIO...")
    df = pa.Table.from_pylist(data)
    table.append(df)

    print(f"✅ Successfully appended {len(data)} rows!")

if __name__ == "__main__":
    run_ingest()