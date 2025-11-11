# Quick Test Checklist - 5 Minutes
**Use this for rapid validation before detailed testing**

---

## ⚡ Quick Build Test (2 minutes)

### Step 1: Clean Build
```
Xcode: Product → Clean Build Folder (Cmd+Shift+K)
```

### Step 2: Build Project
```
Xcode: Product → Build (Cmd+B)
```

### ✅ Success Criteria:
- [ ] Build completes without errors
- [ ] 0 compilation errors shown
- [ ] You see "Build Succeeded" message

### ❌ If Build Fails:
1. Check error message
2. Look for file name and line number
3. Refer to COMPREHENSIVE_CODE_ASSESSMENT.md
4. Report the specific error

---

## ⚡ Quick Runtime Test (3 minutes)

### Step 1: Run App
```
Xcode: Product → Run (Cmd+R)
Select: iPhone 15 Simulator
```

### Step 2: Basic Navigation
1. **Launch** - Does app launch? ✅/❌
2. **Dashboard** - Navigate to dashboard ✅/❌
3. **Settings** - Navigate to settings ✅/❌
4. **Back** - Can navigate back? ✅/❌

### Step 3: Check Console
Look for these messages (not errors):
```
✅ "Loading recent events..." or similar
✅ "Authentication..." messages
❌ No red error messages
❌ No crash reports
```

---

## 🎯 Critical Points to Check

### 1. App Launches ✅/❌
- App opens without crash
- No immediate fatal errors

### 2. No Purple Warnings ✅/❌
- No "Publishing changes from background threads" warnings
- No main thread checker violations

### 3. Views Display ✅/❌
- Dashboard shows (even if empty)
- Settings screen shows
- No blank/frozen screens

### 4. Navigation Works ✅/❌
- Can tap and navigate between views
- Back button works
- No navigation crashes

---

## 📝 Quick Report Template

**Copy and paste this:**

```
BUILD TEST:
[ ] Build succeeded
[ ] Build failed - Error: _______________

RUNTIME TEST:
[ ] App launched
[ ] Dashboard loaded
[ ] Settings loaded
[ ] Navigation worked

CONSOLE:
[ ] No red errors
[ ] Purple warnings present: Yes/No

OVERALL STATUS:
[ ] ✅ Ready for detailed testing
[ ] ❌ Issues found (see below)

ISSUES (if any):
_______________________________________________
```

---

## 🚨 Stop and Report If:

1. **Build fails** - Don't proceed, report error
2. **App crashes on launch** - Report immediately
3. **Multiple red console errors** - Report errors
4. **App freezes/hangs** - Report which screen

---

## ✅ If All Quick Tests Pass:

You're ready for detailed testing! Proceed to TESTING_GUIDE.md for comprehensive tests.

---

## 🔄 Need Help?

**Most Common Issues:**

1. **"Cannot find type 'X'"**
   - Solution: Clean build folder, rebuild

2. **App crashes immediately**
   - Solution: Reset simulator, try again

3. **Console shows errors**
   - Solution: Copy error message, check COMPREHENSIVE_CODE_ASSESSMENT.md

**Still stuck?** Provide the exact error message and which step failed.

---

**Estimated Time:** 5 minutes for quick validation
**Next:** If passes, proceed to full TESTING_GUIDE.md
