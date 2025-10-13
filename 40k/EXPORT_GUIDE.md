# Godot Export Guide for Multiplayer Testing

## Overview

To test multiplayer on different computers, you need to **export the game as a standalone executable**. This allows you to run the game on computers without Godot installed.

## Export Process

### 1. Install Export Templates

First-time setup (one-time only):

1. Open your project in Godot Editor
2. Go to **Editor → Manage Export Templates**
3. Click **Download and Install**
4. Wait for templates to download (this may take a few minutes)

### 2. Configure Export Preset

#### For macOS:

1. Go to **Project → Export...**
2. Click **Add...** and select **macOS**
3. Configure the preset:
   - **Name**: "Warhammer 40K - macOS"
   - **Runnable**: Check this box ✓
   - **Export Path**: Click the folder icon and choose: `exports/macos/Warhammer40K.app`
4. Under **Options**:
   - **Application/Bundle Identifier**: `com.yourdomain.warhammer40k`
   - **Application/Signature**: Leave blank (for testing)
   - **Application/Short Version**: `1.0`
5. Click **Export Project** (bottom right)
6. Choose save location: `exports/macos/`
7. Click **Save**

#### For Windows:

1. Go to **Project → Export...**
2. Click **Add...** and select **Windows Desktop**
3. Configure the preset:
   - **Name**: "Warhammer 40K - Windows"
   - **Runnable**: Check this box ✓
   - **Export Path**: `exports/windows/Warhammer40K.exe`
4. Under **Options**:
   - **Binary Format/64 Bits**: Check ✓ (for 64-bit systems)
   - **Binary Format/Embed PCK**: Check ✓ (single executable)
5. Click **Export Project**
6. Choose save location: `exports/windows/`
7. Click **Save**

#### For Linux:

1. Go to **Project → Export...**
2. Click **Add...** and select **Linux/X11**
3. Configure the preset:
   - **Name**: "Warhammer 40K - Linux"
   - **Runnable**: Check this box ✓
   - **Export Path**: `exports/linux/Warhammer40K.x86_64`
4. Under **Options**:
   - **Binary Format/64 Bits**: Check ✓
   - **Binary Format/Embed PCK**: Check ✓
5. Click **Export Project**
6. Make executable: `chmod +x exports/linux/Warhammer40K.x86_64`

### 3. What Gets Exported

The export process creates:
- **Single executable file** (if "Embed PCK" is checked)
- **Or**: Executable + .pck data file
- All game assets are bundled inside

## Testing Multiplayer on Different Computers

### Scenario 1: Two Computers on Same Network (LAN)

**Best for**: Testing with a friend locally, office/home network

#### Host Computer Setup:

1. Export the game (see above)
2. Copy the exported executable to the host computer
3. Find your local IP address:
   - **macOS/Linux**: Open Terminal, run `ifconfig | grep inet`
   - **Windows**: Open Command Prompt, run `ipconfig`
   - Look for IPv4 address (e.g., `192.168.1.100`)
4. Note your IP address (you'll give this to the client)
5. Check firewall settings (see below)
6. Run the game
7. Click **Multiplayer** → Enter port (e.g., `7777`) → **Host Game**
8. Wait for client to connect

#### Client Computer Setup:

1. Copy the exported executable to the client computer
2. Run the game
3. Click **Multiplayer**
4. Enter host's IP address (e.g., `192.168.1.100`)
5. Enter port (e.g., `7777`)
6. Click **Join Game**
7. Wait for connection

### Scenario 2: Two Instances on Same Computer (Local Testing)

**Best for**: Quick testing without a second computer

1. Export the game
2. Run the exported executable (Instance 1 - Host)
   - Click **Multiplayer** → **Host Game** (port 7777)
3. Run the exported executable again (Instance 2 - Client)
   - Click **Multiplayer** → Enter `127.0.0.1` → **Join Game**
4. On host instance, click **Start Game**

**Note**: You can also mix Godot editor + exported build:
- Run game from Godot editor (Host)
- Run exported executable (Client)

### Scenario 3: Internet Play (Advanced)

**Note**: This requires port forwarding or a relay server (not included in MVP)

For testing over the internet:
1. Host needs to forward port 7777 on their router
2. Host provides their **public IP address** (find at https://whatismyipaddress.com)
3. Client enters host's public IP
4. **Security Warning**: Only do this with trusted friends, as it exposes your network

## Firewall Configuration

### macOS:

1. **System Preferences → Security & Privacy → Firewall**
2. Click lock to make changes
3. **Firewall Options...**
4. Add your game executable to allowed apps
5. Or: Temporarily disable firewall for testing

### Windows:

1. **Windows Security → Firewall & Network Protection**
2. **Allow an app through firewall**
3. **Change settings** → **Allow another app...**
4. Browse to your game executable
5. Check both **Private** and **Public** networks
6. Click **Add**

### Linux:

```bash
# UFW (Ubuntu/Debian)
sudo ufw allow 7777/tcp
sudo ufw allow 7777/udp

# Firewalld (Fedora/CentOS)
sudo firewall-cmd --add-port=7777/tcp --permanent
sudo firewall-cmd --add-port=7777/udp --permanent
sudo firewall-cmd --reload
```

## Directory Structure After Export

```
40k/
├── exports/
│   ├── macos/
│   │   └── Warhammer40K.app          # macOS application bundle
│   ├── windows/
│   │   └── Warhammer40K.exe          # Windows executable
│   └── linux/
│       └── Warhammer40K.x86_64       # Linux executable
```

## File Sharing Methods

### Option 1: USB Drive
- Copy the exported executable to a USB drive
- Transfer to other computer
- Run directly from USB or copy to hard drive

### Option 2: Cloud Storage
- Upload to Google Drive, Dropbox, OneDrive, etc.
- Share link with testing partner
- Download on other computer

### Option 3: Network Share
- On same network, use file sharing:
  - **macOS**: System Preferences → Sharing → File Sharing
  - **Windows**: Right-click folder → Properties → Sharing
  - **Linux**: Use Samba or NFS

### Option 4: Direct Transfer
- **macOS/Linux**: `scp` command
  ```bash
  scp exports/macos/Warhammer40K.app user@192.168.1.100:~/Desktop/
  ```
- **Windows**: Windows Remote Desktop file transfer
- Or use apps like FileZilla, WinSCP

## Common Export Issues

### Issue: "Export templates not found"
**Solution**: Download export templates (see step 1 above)

### Issue: Game won't run on other computer
**Possible causes**:
- Missing dependencies (Windows: Visual C++ Redistributable)
- Wrong architecture (32-bit vs 64-bit)
- Executable permissions not set (Linux/macOS)

**Solutions**:
```bash
# macOS: Remove quarantine flag
xattr -cr Warhammer40K.app

# Linux: Make executable
chmod +x Warhammer40K.x86_64
```

### Issue: "The developer cannot be verified" (macOS)
**Solution**:
- Right-click the app → **Open** (instead of double-clicking)
- Or: System Preferences → Security & Privacy → **Open Anyway**
- Or: Remove quarantine: `xattr -cr Warhammer40K.app`

### Issue: Windows Defender blocks the executable
**Solution**:
- Click **More info** → **Run anyway**
- Or: Add to Windows Defender exceptions

### Issue: Connection fails between computers
**Checklist**:
1. ✓ Both computers on same network?
2. ✓ Host IP address correct?
3. ✓ Port number matches (default: 7777)?
4. ✓ Firewall allows the game?
5. ✓ Host is actually hosting (not just running the game)?

## Quick Export Commands (Advanced)

For faster iteration, you can export from command line:

```bash
# macOS
godot --export "macOS" exports/macos/Warhammer40K.app

# Windows
godot --export "Windows Desktop" exports/windows/Warhammer40K.exe

# Linux
godot --export "Linux/X11" exports/linux/Warhammer40K.x86_64
```

## Testing Checklist

Before sharing with testers:

- [ ] Export completes without errors
- [ ] Executable runs on your computer
- [ ] Main menu appears correctly
- [ ] Multiplayer button is visible
- [ ] Can host a game
- [ ] Can join a game (from another instance)
- [ ] Both players see the same game state
- [ ] Actions sync between players
- [ ] No crash logs or errors

## Performance Considerations

**Export builds are faster than editor builds**:
- Editor: ~30-60 FPS with debug overhead
- Export (debug): ~60-120 FPS
- Export (release): ~120+ FPS (optimized)

For best performance in exports:
1. **Project → Export**
2. Under your preset, **Features** tab:
   - Uncheck **Export With Debug** (for release builds)
3. This removes debug symbols and enables optimizations

## Multiplayer-Specific Testing

### Test Plan for Two Computers:

1. **Connection Test**:
   - [ ] Host can create server
   - [ ] Client can see host IP
   - [ ] Client can connect
   - [ ] Both see "Connected Players: 2/2"

2. **Deployment Test**:
   - [ ] Host starts game
   - [ ] Both load into battlefield
   - [ ] Player 1 can deploy units
   - [ ] Player 2 sees Player 1's deployments

3. **Turn Test**:
   - [ ] Active player indicator correct
   - [ ] Only active player can act
   - [ ] Turn timer works (90 seconds)
   - [ ] Turn changes properly

4. **RNG Test**:
   - [ ] Dice rolls are identical on both clients
   - [ ] Advance rolls match
   - [ ] Combat rolls match

5. **Disconnect Test**:
   - [ ] Game handles disconnect gracefully
   - [ ] Error message appears
   - [ ] Can return to menu

## Recommended Testing Setup

**Ideal**: Two different computers on same network
- Most realistic testing scenario
- Tests actual network latency
- Identifies platform-specific issues

**Alternative**: Two instances on same computer
- Faster iteration
- Good for initial testing
- Less realistic (no network latency)

**Next Level**: Test over internet
- Port forwarding required
- Tests real-world conditions
- Higher latency

## Support for Different Platforms

Your current setup (macOS) can export for:
- ✅ macOS (native)
- ✅ Windows (cross-compile)
- ✅ Linux (cross-compile)
- ✅ Web (HTML5) - requires additional setup

**No additional tools needed** for basic exports!

## Next Steps

1. Export for your platform
2. Test locally (two instances)
3. Copy to another computer on same network
4. Test LAN multiplayer
5. Share with testers
6. Iterate based on feedback

## Additional Resources

- **Godot Export Docs**: https://docs.godotengine.org/en/stable/tutorials/export/
- **ENet Docs**: https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html
- **Port Forwarding Guide**: https://portforward.com/

---

**TIP**: For rapid testing, keep the Godot editor open on one computer (Host) and run the exported build on another computer (Client). This lets you quickly iterate without re-exporting after every change.