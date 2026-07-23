# Facebook Login — setup

The app + server code for "Continue with Facebook" is complete. To switch it on we
just need a Facebook app (created under the client's own Facebook account) and its
three values dropped into the placeholders below.

## What to get from developers.facebook.com

1. My Apps → **Create App** → "Authenticate and request data from users with
   Facebook Login" (older UI: "Consumer").
2. Name it **ListIt**, add the **Facebook Login** product.
3. **Settings → Basic**: copy the **App ID** and **App Secret**.
4. **Settings → Advanced → Security**: copy the **Client Token**.
5. Add platforms in Settings → Basic:
   - **Android**: package `com.example.listit_app` (or the final applicationId),
     plus the release/debug **key hashes** (I generate these from the signing key).
   - **iOS**: the bundle identifier.
6. Add a **Privacy Policy URL** (https://listit.im/privacypolicy) and a **Data
   Deletion** URL/callback (required before the app can go Live).
7. Toggle the app to **Live**. `public_profile` + `email` need no App Review.

## Where the values go (replace every `REPLACE_WITH_...`)

- Server: `FB_APP_ID` and `FB_APP_SECRET` env vars on api.listit.im (used to
  verify the token server-side — the endpoint already reads them).
- `android/app/src/main/res/values/strings.xml`
  - `facebook_app_id` → App ID
  - `fb_login_protocol_scheme` → `fb` + App ID
  - `facebook_client_token` → Client Token
- `ios/Runner/Info.plist`
  - `FacebookAppID`, the `fb<APPID>` URL scheme, `FacebookClientToken`

## How it works

1. App shows "Continue with Facebook" on the sign-in screen.
2. Facebook returns a short-lived user access token to the app.
3. App sends it to `POST /api/auth/facebook`.
4. Server verifies the token with Facebook's Graph API, reads the real
   name / email / profile picture, creates or finds the user, and returns our
   normal Listit JWT — identical to email login from there on.

No password is stored for Facebook users; identity is keyed on the Facebook id
(and email when the user shares it).
