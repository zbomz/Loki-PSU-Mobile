# Installing Your IPA on iPhone

## 🎯 **You Downloaded the IPA! Here's What to Do Next:**

Since you have an **unsigned IPA** from GitHub Actions, you have a few options:

### **Option 1: Diawi (Easiest - Requires Signing)**

**Problem**: Diawi requires properly signed IPAs. Your GitHub build is unsigned.

**Solution**: You need to complete the certificate setup first:

1. **Get your certificate**:
   - Go to [developer.apple.com](https://developer.apple.com/account)
   - Navigate to Certificates → Download your development certificate (.cer file)
   - Convert to .p12 (see APPLE_SETUP_README.md)

2. **Add secrets to GitHub**:
   - IOS_CERTIFICATE (base64)
   - IOS_CERTIFICATE_PASSWORD
   - IOS_PROVISIONING_PROFILE (base64) - **You already have this!**

3. **Push new code** to trigger signed build

4. **Download signed IPA** → Upload to Diawi → Install on iPhone

---

### **Option 2: Use Xcode (If You Have Access to a Mac)**

If you can borrow a Mac:
1. Open Xcode
2. Window → Devices and Simulators
3. Connect iPhone
4. Drag IPA onto device list
5. Install directly

---

### **Option 3: TestFlight (More Setup)**

1. Complete App Store Connect setup
2. Upload build via Transporter app
3. Add yourself as internal tester
4. Install via TestFlight app on iPhone

---

### **Option 4: Sideload with AltStore (Free Alternative)**

**AltStore** lets you install unsigned IPAs without Apple Developer account:

1. **Download AltStore**: [altstore.io](https://altstore.io)
2. **Install on Windows PC**
3. **Connect iPhone** via USB
4. **Install AltStore app** on iPhone
5. **Sideload your IPA** through AltStore

**Limitations**:
- Apps expire after 7 days (need to re-sign)
- Limited to 3 apps at once
- Still requires Apple ID (free)

---

### **Option 5: Cydia Impactor (Alternative)**

Similar to AltStore but different tool.

---

## 🚀 **Recommended Path:**

Since you already have the **provisioning profile** (`mobileprovision_base64.txt`), you're almost there!

### **Quick Steps:**

1. **Get your certificate**:
   - Download development certificate from Apple Developer
   - Convert to .p12 using OpenSSL

2. **Encode certificate to base64**:
   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("certificate.p12"))
   ```

3. **Add GitHub Secrets**:
   - Go to: https://github.com/zbomz/Loki-PSU-Mobile/settings/secrets/actions
   - Add: `IOS_CERTIFICATE` (base64 string)
   - Add: `IOS_CERTIFICATE_PASSWORD` (your password)
   - Add: `IOS_PROVISIONING_PROFILE` (content from `mobileprovision_base64.txt`)

4. **Update workflow** to use signing

5. **Push code** → Get signed IPA

6. **Install via Diawi or directly**

---

## 📱 **Immediate Option: AltStore**

If you want to test **right now** without waiting:

1. Download [AltStore](https://altstore.io)
2. Install on your Windows PC
3. Connect iPhone via USB
4. Sideload the unsigned IPA
5. Test your app!

**This gets you testing in ~15 minutes!**

---

## ❓ **What Do You Want to Do?**

1. **Complete certificate setup** → Get signed IPA → Install via Diawi
2. **Use AltStore** → Install unsigned IPA right now
3. **Wait for Mac access** → Use Xcode
4. **Something else**

Let me know which path you want to take!