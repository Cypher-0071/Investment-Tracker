# Supabase Setup Guide

## Migration Complete! ✅

Your Flutter app has been successfully migrated from Firebase to Supabase.

## What Has Been Changed

### Dependencies
- ✅ Removed: `firebase_core`, `cloud_firestore`, `firebase_auth`, `firebase_storage`
- ✅ Added: `supabase_flutter: ^2.5.6`
- ✅ Kept: `google_sign_in` (still needed for Google OAuth)

### Files Changed
- ✅ `pubspec.yaml` - Updated dependencies
- ✅ `lib/main.dart` - Replaced Firebase initialization with Supabase
- ✅ `lib/services/cloud_sync_service.dart` → `lib/services/supabase_sync_service.dart`
- ✅ `lib/services/firebase_storage_service.dart` → `lib/services/supabase_storage_service.dart`
- ✅ Removed all Firebase configuration files
- ✅ Removed Firebase from Android build files

## Next Steps

### 1. Create a Supabase Project

1. Go to [https://supabase.com](https://supabase.com)
2. Sign up for a free account (if you don't have one)
3. Click "New Project"
4. Choose an organization or create one
5. Fill in project details:
   - **Name**: `portfolio-tracker` (or any name you prefer)
   - **Database Password**: Create a strong password (save it!)
   - **Region**: Choose closest to you
   - **Pricing Plan**: Free (for now)
6. Click "Create new project"
7. Wait 2-3 minutes for the project to be created

### 2. Get Your Supabase Credentials

1. Once your project is ready, go to **Settings** (gear icon) → **API**
2. You'll find:
   - **Project URL**: `https://xxxxxxxxxxxxx.supabase.co`
   - **anon public key**: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...`

### 3. Update `lib/main.dart`

Replace the placeholder values in `lib/main.dart`:

```dart
await Supabase.initialize(
  url: 'https://YOUR_PROJECT_REF.supabase.co',  // Replace with your Project URL
  anonKey: 'YOUR_ANON_KEY',                     // Replace with your anon key
  authOptions: const FlutterAuthClientOptions(
    authFlowType: AuthFlowType.pkce,
  ),
);
```

### 4. Set Up Database Tables in Supabase

Go to **SQL Editor** in your Supabase dashboard and run these SQL commands:

#### Create `transactions` table:
```sql
-- Create transactions table
CREATE TABLE IF NOT EXISTS transactions (
  id TEXT PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  amount DECIMAL(10, 2) NOT NULL,
  category TEXT NOT NULL,
  name TEXT,
  description TEXT,
  date TIMESTAMP WITH TIME ZONE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;

-- Create policy: Users can only see their own transactions
CREATE POLICY "Users can view own transactions" ON transactions
  FOR SELECT USING (auth.uid() = user_id);

-- Create policy: Users can insert their own transactions
CREATE POLICY "Users can insert own transactions" ON transactions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Create policy: Users can update their own transactions
CREATE POLICY "Users can update own transactions" ON transactions
  FOR UPDATE USING (auth.uid() = user_id);

-- Create policy: Users can delete their own transactions
CREATE POLICY "Users can delete own transactions" ON transactions
  FOR DELETE USING (auth.uid() = user_id);
```

#### Create `profiles` table:
```sql
-- Create profiles table
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT,
  display_name TEXT,
  photo_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Create policy: Users can view own profile
CREATE POLICY "Users can view own profile" ON profiles
  FOR SELECT USING (auth.uid() = id);

-- Create policy: Users can update own profile
CREATE POLICY "Users can update own profile" ON profiles
  FOR UPDATE USING (auth.uid() = id);

-- Create policy: Users can insert own profile
CREATE POLICY "Users can insert own profile" ON profiles
  FOR INSERT WITH CHECK (auth.uid() = id);
```

### 5. Set Up Storage Bucket

1. Go to **Storage** in your Supabase dashboard
2. Click **New bucket**
3. Name: `profile_images`
4. Make it **Public** (or keep private if you prefer)
5. Click **Create bucket**

### 6. Configure Google OAuth (Optional)

If you want to use Google Sign-In:

1. Go to **Authentication** → **Providers** in Supabase
2. Click on **Google**
3. Enable it
4. You'll need to add:
   - **Client ID**
   - **Client Secret**
   
   (Get these from [Google Cloud Console](https://console.cloud.google.com))

### 7. Configure Deep Links (For Mobile)

For Google Sign-In to work on mobile, you need to configure deep links.

#### Android:
Edit `android/app/src/main/AndroidManifest.xml` and add:

```xml
<activity
  android:name=".MainActivity"
  ...>
  <!-- Add this inside the activity -->
  <intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data
      android:scheme="io.supabase.portfolio"
      android:host="login-callback" />
  </intent-filter>
</activity>
```

#### iOS:
Add to `ios/Runner/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>io.supabase.portfolio</string>
    </array>
  </dict>
</array>
```

### 8. Clean and Rebuild

```bash
flutter clean
flutter pub get
flutter run
```

## Features Available

✅ **Google Sign-In** - OAuth authentication  
✅ **Cloud Sync** - Sync transactions across devices  
✅ **Cloud Storage** - Upload profile pictures  
✅ **Offline Support** - Local backup with SharedPreferences  
✅ **Real-time** - Automatic data synchronization  

## Troubleshooting

### Error: "Supabase client not initialized"
- Make sure you've updated `lib/main.dart` with your Supabase credentials

### Error: "permission denied for table transactions"
- Make sure you've created the RLS policies (run the SQL commands above)

### Error: "bucket not found"
- Make sure you've created the `profile_images` bucket in Storage

### Google Sign-In not working
- Make sure you've configured deep links in AndroidManifest.xml or Info.plist

## Additional Resources

- [Supabase Flutter Documentation](https://supabase.com/docs/reference/dart/introduction)
- [Supabase Auth Guide](https://supabase.com/docs/guides/auth)
- [Supabase Storage Guide](https://supabase.com/docs/guides/storage)
- [Supabase Row Level Security](https://supabase.com/docs/guides/auth/row-level-security)



