"""
Custom Alert Router - Enterprise-grade alert routing for homelab
Handles alerts from Prometheus/Alertmanager and Uptime Kuma

Features:
- Multi-source alert ingestion (Alertmanager, Uptime Kuma)
- Message formatting and enrichment
- Deduplication with TTL
- Silence rules with time windows
- Escalation policies (retry on failure)
- Priority-based routing to Discord channels
- Alert history and metrics
"""

from fastapi import FastAPI, Request, HTTPException, BackgroundTasks
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from typing import Dict, List, Optional, Any
from datetime import datetime, timedelta
from collections import defaultdict
import httpx
import hashlib
import asyncio
import logging
import os
from enum import Enum

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Alert Router", version="1.0.0")

# Configuration from environment variables
DISCORD_WEBHOOK_CRITICAL = os.getenv("DISCORD_WEBHOOK_CRITICAL", "")
DISCORD_WEBHOOK_WARNING = os.getenv("DISCORD_WEBHOOK_WARNING", "")
DISCORD_WEBHOOK_INFO = os.getenv("DISCORD_WEBHOOK_INFO", "")

# In-memory storage (use Redis for production)
alert_history: Dict[str, datetime] = {}  # Alert hash -> last sent time
silences: List[Dict] = []  # Silence rules
metrics = defaultdict(int)  # Alert metrics

# Deduplication TTL (don't send same alert within this time)
DEDUP_TTL_SECONDS = 300  # 5 minutes

class Severity(str, Enum):
    CRITICAL = "critical"
    WARNING = "warning"
    INFO = "info"

class AlertSource(str, Enum):
    ALERTMANAGER = "alertmanager"
    UPTIME_KUMA = "uptime-kuma"

def get_alert_hash(alert: Dict) -> str:
    """Generate unique hash for alert deduplication"""
    # Use alertname + instance + labels for hash
    key_parts = [
        alert.get("labels", {}).get("alertname", ""),
        alert.get("labels", {}).get("instance", ""),
        alert.get("labels", {}).get("namespace", ""),
        alert.get("labels", {}).get("pod", ""),
    ]
    key = "|".join(filter(None, key_parts))
    return hashlib.md5(key.encode()).hexdigest()

def is_duplicate(alert_hash: str) -> bool:
    """Check if alert was recently sent"""
    if alert_hash in alert_history:
        last_sent = alert_history[alert_hash]
        if datetime.now() - last_sent < timedelta(seconds=DEDUP_TTL_SECONDS):
            logger.info(f"Alert {alert_hash} is duplicate, skipping")
            metrics["duplicates_filtered"] += 1
            return True
    return False

def is_silenced(alert: Dict) -> bool:
    """Check if alert matches any silence rules"""
    labels = alert.get("labels", {})
    
    for silence in silences:
        if not silence.get("active", True):
            continue
            
        # Check if silence has expired
        if silence.get("ends_at"):
            ends_at = datetime.fromisoformat(silence["ends_at"])
            if datetime.now() > ends_at:
                silence["active"] = False
                continue
        
        # Check if labels match
        matchers = silence.get("matchers", {})
        if all(labels.get(k) == v for k, v in matchers.items()):
            logger.info(f"Alert silenced by rule: {silence.get('name')}")
            metrics["alerts_silenced"] += 1
            return True
    
    return False

def format_alertmanager_message(data: Dict) -> Dict[str, Any]:
    """Format Alertmanager webhook into Discord embed"""
    alerts = data.get("alerts", [])
    status = data.get("status", "firing")
    
    # Determine severity from first alert
    severity = Severity.WARNING
    if alerts:
        sev = alerts[0].get("labels", {}).get("severity", "warning").lower()
        severity = Severity(sev) if sev in Severity.__members__.values() else Severity.WARNING
    
    # Build embed
    color_map = {
        Severity.CRITICAL: 15158332,  # Red
        Severity.WARNING: 16776960,   # Yellow
        Severity.INFO: 3447003,       # Blue
    }
    
    emoji_map = {
        Severity.CRITICAL: "🔴",
        Severity.WARNING: "🟡",
        Severity.INFO: "🔵",
    }
    
    color = color_map.get(severity, 8421504)
    emoji = emoji_map.get(severity, "⚪")
    
    # Format alert list
    fields = []
    for alert in alerts[:10]:  # Limit to 10 alerts per message
        labels = alert.get("labels", {})
        annotations = alert.get("annotations", {})
        
        alert_name = labels.get("alertname", "Unknown")
        instance = labels.get("instance", "")
        namespace = labels.get("namespace", "")
        node = labels.get("kubernetes_node", "")
        
        description = annotations.get("description", annotations.get("summary", "No description"))
        
        # Build field value
        value_parts = [f"**{description}**"]
        if instance:
            value_parts.append(f"Instance: `{instance}`")
        if node:
            value_parts.append(f"Node: `{node}`")
        if namespace:
            value_parts.append(f"Namespace: `{namespace}`")
        
        fields.append({
            "name": f"{emoji} {alert_name}",
            "value": "\n".join(value_parts),
            "inline": False
        })
    
    title = f"{emoji} {len(alerts)} Alert(s) {status.upper()}"
    
    embed = {
        "title": title,
        "color": color,
        "fields": fields,
        "timestamp": datetime.utcnow().isoformat(),
        "footer": {
            "text": f"Source: Prometheus Alertmanager | Severity: {severity.value}"
        }
    }
    
    return {
        "embeds": [embed],
        "username": f"{emoji} Alert Router",
    }

def format_uptime_kuma_message(data: Dict) -> Dict[str, Any]:
    """Format Uptime Kuma webhook into Discord embed"""
    # Uptime Kuma webhook format
    heartbeat = data.get("heartbeat", {})
    monitor = data.get("monitor", {})
    
    status = heartbeat.get("status", 0)  # 0=down, 1=up
    is_down = status == 0
    
    severity = Severity.CRITICAL if is_down else Severity.INFO
    
    color = 15158332 if is_down else 5763719  # Red or Green
    emoji = "🔴" if is_down else "✅"
    
    monitor_name = monitor.get("name", "Unknown")
    monitor_url = monitor.get("url", "")
    msg = data.get("msg", "Status changed")
    
    embed = {
        "title": f"{emoji} {monitor_name} - {'DOWN' if is_down else 'UP'}",
        "description": msg,
        "color": color,
        "fields": [
            {
                "name": "URL",
                "value": monitor_url or "N/A",
                "inline": False
            },
            {
                "name": "Status",
                "value": "🔴 Service Down" if is_down else "✅ Service Up",
                "inline": True
            }
        ],
        "timestamp": datetime.utcnow().isoformat(),
        "footer": {
            "text": "Source: Uptime Kuma"
        }
    }
    
    return {
        "embeds": [embed],
        "username": f"{emoji} Uptime Monitor",
    }

async def send_to_discord(webhook_url: str, message: Dict, retries: int = 3):
    """Send message to Discord with retry logic (escalation)"""
    if not webhook_url:
        logger.warning("Discord webhook URL not configured")
        return False
    
    async with httpx.AsyncClient() as client:
        for attempt in range(retries):
            try:
                response = await client.post(webhook_url, json=message, timeout=10.0)
                if response.status_code == 204:
                    logger.info("Alert sent to Discord successfully")
                    metrics["alerts_sent"] += 1
                    return True
                else:
                    logger.error(f"Discord returned status {response.status_code}")
            except Exception as e:
                logger.error(f"Failed to send to Discord (attempt {attempt+1}/{retries}): {e}")
                if attempt < retries - 1:
                    await asyncio.sleep(2 ** attempt)  # Exponential backoff
    
    metrics["alerts_failed"] += 1
    return False

def get_webhook_url(severity: Severity) -> str:
    """Route to appropriate Discord channel based on severity"""
    webhook_map = {
        Severity.CRITICAL: DISCORD_WEBHOOK_CRITICAL,
        Severity.WARNING: DISCORD_WEBHOOK_WARNING,
        Severity.INFO: DISCORD_WEBHOOK_INFO,
    }
    
    # Fallback to critical webhook if specific one not configured
    return webhook_map.get(severity) or DISCORD_WEBHOOK_CRITICAL

@app.post("/webhook/alertmanager")
async def alertmanager_webhook(request: Request, background_tasks: BackgroundTasks):
    """Receive alerts from Prometheus Alertmanager"""
    try:
        data = await request.json()
        logger.info(f"Received Alertmanager webhook: {data.get('status')}")
        
        metrics["alerts_received"] += 1
        
        alerts = data.get("alerts", [])
        if not alerts:
            return JSONResponse({"status": "no alerts"})
        
        # Process each alert
        for alert in alerts:
            alert_hash = get_alert_hash(alert)
            
            # Check deduplication
            if is_duplicate(alert_hash):
                continue
            
            # Check silence rules
            if is_silenced(alert):
                continue
            
            # Determine severity
            severity_str = alert.get("labels", {}).get("severity", "warning").lower()
            severity = Severity(severity_str) if severity_str in Severity.__members__.values() else Severity.WARNING
            
            # Format message
            message = format_alertmanager_message({"alerts": [alert], "status": data.get("status")})
            
            # Get webhook URL based on severity
            webhook_url = get_webhook_url(severity)
            
            # Send to Discord (with escalation/retry)
            background_tasks.add_task(send_to_discord, webhook_url, message)
            
            # Update history
            alert_history[alert_hash] = datetime.now()
        
        return JSONResponse({"status": "processed", "count": len(alerts)})
        
    except Exception as e:
        logger.error(f"Error processing Alertmanager webhook: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/webhook/uptime-kuma")
async def uptime_kuma_webhook(request: Request, background_tasks: BackgroundTasks):
    """Receive alerts from Uptime Kuma"""
    try:
        data = await request.json()
        logger.info(f"Received Uptime Kuma webhook")
        
        metrics["alerts_received"] += 1
        
        # Determine if this is a down alert
        heartbeat = data.get("heartbeat", {})
        is_down = heartbeat.get("status", 1) == 0
        
        severity = Severity.CRITICAL if is_down else Severity.INFO
        
        # Format message
        message = format_uptime_kuma_message(data)
        
        # Get webhook URL
        webhook_url = get_webhook_url(severity)
        
        # Send to Discord
        background_tasks.add_task(send_to_discord, webhook_url, message)
        
        return JSONResponse({"status": "processed"})
        
    except Exception as e:
        logger.error(f"Error processing Uptime Kuma webhook: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/silences")
async def create_silence(silence: Dict):
    """Create a silence rule"""
    silence["active"] = True
    silence["created_at"] = datetime.now().isoformat()
    silences.append(silence)
    logger.info(f"Silence created: {silence.get('name')}")
    return JSONResponse({"status": "created", "silence": silence})

@app.get("/silences")
async def list_silences():
    """List all silence rules"""
    return JSONResponse({"silences": silences})

@app.delete("/silences/{index}")
async def delete_silence(index: int):
    """Delete a silence rule"""
    if 0 <= index < len(silences):
        removed = silences.pop(index)
        return JSONResponse({"status": "deleted", "silence": removed})
    raise HTTPException(status_code=404, detail="Silence not found")

@app.get("/metrics")
async def get_metrics():
    """Get alert router metrics"""
    return JSONResponse({
        "metrics": dict(metrics),
        "alert_history_size": len(alert_history),
        "active_silences": len([s for s in silences if s.get("active")])
    })

@app.get("/health")
async def health():
    """Health check endpoint"""
    return JSONResponse({"status": "healthy", "timestamp": datetime.now().isoformat()})

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)




