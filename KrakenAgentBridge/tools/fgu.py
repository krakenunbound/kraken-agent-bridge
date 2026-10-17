"""Command-line access to the bridge tools: the same tools the MCP server gives an agent.
For agents without MCP (or for scripts): they can run this instead.
usage: python fgu.py <tool> '<json args>'
   e.g. python fgu.py fgu_status
        python fgu.py fgu_db_list '{"path":"charsheet"}'
        python fgu.py fgu_call '{"package":"ChatManager","fn":"SystemMessage","args":["Hello from the bridge"]}'
"""
import json
import sys
from pathlib import Path

# tools/ sits next to server/ inside the KrakenAgentBridge extension folder.
BRIDGE_SERVER = Path(__file__).resolve().parent.parent / "server"
sys.path.insert(0, str(BRIDGE_SERVER))
import fgu_mcp  # noqa: E402

if len(sys.argv) < 2:
    print(__doc__)
    raise SystemExit(2)

name = sys.argv[1]
args = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
try:
    print(json.dumps(fgu_mcp.call_tool(name, args), indent=1))
except Exception as exc:
    print(f"{type(exc).__name__}: {exc}")
    raise SystemExit(1)
