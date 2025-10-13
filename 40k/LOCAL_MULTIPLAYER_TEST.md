# Local Multiplayer Testing Guide (Same Mac)

## Quick Start - Two Methods

### Method 1: Export Once, Run Twice (Recommended)

This is the **fastest** way to test multiplayer on your Mac.

#### Step 1: Export the Game

1. Open your project in Godot
2. **Project** → **Export...**
3. Click **Add...** → **macOS**
4. Set **Export Path**: `exports/macos/Warhammer40K.app`
5. Check **Runnable** ✓
6. Click **Export Project**

#### Step 2: Launch Two Instances

Open Terminal and run:

```bash
# Navigate to your project
cd /Users/robertocallaghan/Documents/claude/godotv2/40k

# Launch first instance (Host)
open -n exports/macos/Warhammer40K.app

# Wait 2 seconds, then launch second instance (Client)
sleep 2 && open -n exports/macos/Warhammer40K.app
```

The `-n` flag tells macOS to open a **new instance** instead of focusing the existing one.

#### Step 3: Set Up Host (First Window)

1. Click **Multiplayer**
2. Port: `7777` (default is fine)
3. Click **Host Game**
4. Wait for "Waiting for player 2..."

#### Step 4: Set Up Client (Second Window)

1. Click **Multiplayer**
2. IP Address: `127.0.0.1` (localhost - already default)
3. Port: `7777`
4. Click **Join Game**
5. Wait for connection

#### Step 5: Start the Game

1. Go back to **Host window**
2. You should see "Connected Players: 2/2"
3. Click **Start Game**
4. Both windows transition to battlefield!

---

### Method 2: Godot Editor + Exported Build (Faster Iteration)

This method is **best for development** because you can make changes quickly.

#### Step 1: Export Once (if not done)

Same as Method 1 above.

#### Step 2: Launch Host from Godot Editor

1. Open project in Godot
2. Press **F5** (or click ▶ Play button)
3. Main menu appears
4. Click **Multiplayer** → **Host Game** (port 7777)

#### Step 3: Launch Client from Exported Build

In Terminal:

```bash
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
open exports/macos/Warhammer40K.app
```

Or just double-click `Warhammer40K.app` in Finder.

#### Step 4: Connect Client

1. In the exported build window
2. Click **Multiplayer**
3. IP: `127.0.0.1`
4. Port: `7777`
5. Click **Join Game**

#### Step 5: Start Game from Editor

1. Go back to Godot editor window
2. See "Connected Players: 2/2"
3. Click **Start Game**

---

## Troubleshooting

### Issue: "Address already in use"

**Cause**: Port 7777 is already taken by another instance.

**Solution**:
```bash
# Find what's using port 7777
lsof -i :7777

# Kill it if needed
kill -9 <PID>

# Or use a different port (e.g., 7778)
```

### Issue: Can't see second window

**Cause**: Both windows opened in same position.

**Solution**:
- Use **Mission Control** (swipe up with 3 fingers)
- Or **Cmd + Tab** to switch between windows
- Drag one window to the side

### Issue: "Connection failed"

**Checklist**:
- ✓ Host is actually hosting (clicked "Host Game")?
- ✓ Both using port 7777?
- ✓ Client using IP `127.0.0.1`?
- ✓ Firewall not blocking (unlikely for localhost)?

**Fix**: Quit both instances, start fresh:
```bash
# Kill all instances
killall Warhammer40K

# Start over
open -n exports/macos/Warhammer40K.app
sleep 2 && open -n exports/macos/Warhammer40K.app
```

### Issue: Second instance won't open

**Cause**: macOS preventing multiple instances.

**Solution**: Use the `-n` flag:
```bash
open -n exports/macos/Warhammer40K.app  # Note the -n!
```

### Issue: Both windows controlling same player

**Cause**: Not actually running two separate instances.

**Solution**: Make sure you see **two separate windows** in Mission Control or Cmd+Tab.

---

## Testing Checklist

### Connection Test
- [ ] Host can create server
- [ ] Client can connect
- [ ] Both see "Connected Players: 2/2"
- [ ] Status messages update correctly

### Gameplay Test
- [ ] Host clicks "Start Game"
- [ ] Both windows load battlefield
- [ ] Window 1 controls Player 1 (blue units)
- [ ] Window 2 controls Player 2 (red units)
- [ ] Turn indicator shows active player
- [ ] Non-active player cannot act

### Network Sync Test
- [ ] Player 1 deploys a unit → Player 2 sees it
- [ ] Player 2 deploys a unit → Player 1 sees it
- [ ] Unit positions identical in both windows
- [ ] Turn changes sync both windows
- [ ] Dice rolls match (deterministic RNG)

### Error Handling Test
- [ ] Close client window → host shows disconnect
- [ ] Close host window → client shows disconnect
- [ ] Return to lobby after disconnect
- [ ] Can reconnect after disconnect

---

## Advanced: Automated Testing Script

Save this as `test_multiplayer.sh`:

```bash
#!/bin/bash

# Navigate to project
cd /Users/robertocallaghan/Documents/claude/godotv2/40k

# Kill any existing instances
killall Warhammer40K 2>/dev/null

# Export if needed
if [ ! -f "exports/macos/Warhammer40K.app/Contents/MacOS/Warhammer40K" ]; then
    echo "Export not found. Please export the game first."
    exit 1
fi

echo "Launching Host instance..."
open -n exports/macos/Warhammer40K.app

sleep 3

echo "Launching Client instance..."
open -n exports/macos/Warhammer40K.app

echo ""
echo "Two instances launched!"
echo ""
echo "Host (first window): Multiplayer → Host Game (port 7777)"
echo "Client (second window): Multiplayer → Join (127.0.0.1:7777)"
echo ""
echo "Press Ctrl+C to kill both instances when done."
echo ""

# Wait for user interrupt
trap "killall Warhammer40K; echo 'Instances killed.'; exit" INT
while true; do sleep 1; done
```

Make it executable and run:

```bash
chmod +x test_multiplayer.sh
./test_multiplayer.sh
```

---

## Window Management Tips

### Option 1: Side-by-Side (Recommended)

1. Launch both instances
2. Drag Host window to **left half** of screen
3. Drag Client window to **right half** of screen
4. Now you can see both at once!

### Option 2: Separate Desktops

1. Launch both instances
2. Swipe up with 3 fingers (Mission Control)
3. Drag one window to **Desktop 2** at top
4. Swipe left/right to switch between desktops

### Option 3: Window Resizing

```bash
# Make windows smaller so both fit on screen
# (This happens automatically if you drag them side-by-side)
```

---

## Performance Notes

Running two instances on the same Mac:

**Expected**:
- ✅ Both run smoothly on modern Mac
- ✅ Combined CPU usage: ~20-40%
- ✅ RAM usage: ~500MB-1GB total
- ✅ No network latency (localhost)

**If Laggy**:
- Close other applications
- Use Activity Monitor to check CPU/RAM
- Consider using Godot editor for host (more optimized)

---

## Debugging Tips

### Enable Console Output

To see network messages:

```bash
# Run with console output visible
/path/to/Warhammer40K.app/Contents/MacOS/Warhammer40K
```

This shows all `print()` statements from the game.

### Check Network Activity

```bash
# See if port 7777 is listening
lsof -i :7777

# Should show something like:
# COMMAND    PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
# Warhammer 1234 user   10u  IPv4  12345      0t0  TCP *:7777 (LISTEN)
```

### Monitor Network Traffic

```bash
# Install if needed
brew install wireshark

# Or use built-in tcpdump
sudo tcpdump -i lo0 port 7777
```

---

## Quick Reference

### Launch Two Instances
```bash
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
open -n exports/macos/Warhammer40K.app
sleep 2 && open -n exports/macos/Warhammer40K.app
```

### Host Setup
- Multiplayer → Host Game (port 7777)

### Client Setup
- Multiplayer → IP: 127.0.0.1 → Port: 7777 → Join Game

### Kill All Instances
```bash
killall Warhammer40K
```

### Check What's Running
```bash
ps aux | grep Warhammer40K
```

---

## What You Should See

### Successful Connection:

**Host Window:**
```
Status: Hosting on port 7777
Waiting for player 2 to connect...
[After client joins]
Status: Player 2 connected!
Connected Players: 2/2
[Start Game button enabled]
```

**Client Window:**
```
Status: Connecting to 127.0.0.1:7777...
[After connection]
Status: Connected to host
Connected Players: 2/2 (You are Player 2)
Waiting for host to start game...
```

### In Godot Console (if using Method 2):

```
NetworkManager: Hosting on port 7777
NetworkManager: Peer connected - 2
MultiplayerLobby: Peer connected - 2
```

---

## Next Steps After Local Testing

Once multiplayer works locally:

1. ✅ Test on **two different Macs** (same network)
   - Use actual IP instead of 127.0.0.1
   - Example: `192.168.1.100`

2. ✅ Test **Mac → Windows** (cross-platform)
   - Export Windows build
   - Transfer to PC
   - Test connection

3. ✅ Test **over internet** (advanced)
   - Requires port forwarding
   - Use public IP instead of local

---

## Common Multiplayer Scenarios to Test

### Scenario 1: Normal Game Flow
1. Both players connect
2. Host starts game
3. Player 1 deploys units
4. Player 2 deploys units
5. Play through a full turn
6. Verify actions sync

### Scenario 2: Early Disconnect
1. Connect both players
2. **Before starting game**, close client
3. Host should show disconnect message
4. Verify can return to lobby

### Scenario 3: Mid-Game Disconnect
1. Connect and start game
2. Deploy some units
3. Close client mid-turn
4. Host should handle gracefully
5. Verify error message appears

### Scenario 4: Turn Timer
1. Connect and start game
2. Wait 90+ seconds without acting
3. Verify turn timer expires
4. Check game over message

### Scenario 5: RNG Sync
1. Connect and start game
2. Perform advance move (requires dice roll)
3. **Compare dice results in both windows**
4. Should be identical (deterministic)

---

## FAQ

**Q: Do I need to export every time I make a change?**
A: Use Method 2 (Godot editor + export). Only host needs to be in editor.

**Q: Can I test with 3+ players?**
A: Not yet - current implementation is 2-player only.

**Q: Does localhost test real network conditions?**
A: No - it's instant (no latency). Test on LAN for realistic networking.

**Q: Can I run host and client on different monitors?**
A: Yes! Just drag windows to different monitors.

**Q: What if I don't have a second monitor?**
A: Use side-by-side windows or separate desktops (Mission Control).

---

## Summary

**Fastest Way to Test:**
```bash
# One-liner to test multiplayer
cd /Users/robertocallaghan/Documents/claude/godotv2/40k && \
open -n exports/macos/Warhammer40K.app && \
sleep 2 && open -n exports/macos/Warhammer40K.app
```

Then:
1. Window 1: Multiplayer → Host Game
2. Window 2: Multiplayer → Join (127.0.0.1)
3. Window 1: Start Game
4. Play!

Good luck testing! 🎮