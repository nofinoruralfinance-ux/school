# NTCCSL Account Portal

Flutter app for viewing ledger entries, daily/weekly/monthly collections, and users backed by a Google Apps Script web app.

## Configure the data service

Screens are organized as separate Dart files under `lib/pages/`: login, registration, dashboard, ledger, collections, users, and the signed-in user's profile. The dashboard summarizes ledger balances, collection totals, people, and recent ledger activity; use its collection cards to open the full collection pages. Profile details are available from the account icon in the app bar.

Choose **Appearance** from the navigation drawer to use the device's **System** setting or force **Light** or **Dark** mode. System mode follows the device appearance; page surfaces, forms, dialogs, and headers adapt to the selected theme.

The Apps Script backend is provided in [`Code.gs`](./Code.gs). Attach it to the Google Sheet that will hold the portal data, run `setupAccountPortal` and approve its Sheets and Drive access (setup also creates the private profile-image folder), create the first admin, then deploy the web app as described below.

The Flutter screens are separate files under `lib/pages/`, with shared API code in `lib/services/api_service.dart`. The sign-in screen has separate **Admin / Collector** and **Member** choices; the server verifies that credentials belong to the selected role group, and the account's role—not the selected tab—determines permissions. Each Member signs in with their own email and password. Admins can activate/deactivate that Member's Daily, Weekly, and Monthly report tabs individually from Users → Edit; the backend also blocks report requests for inactive tabs. Members remain strictly view-only: collection, ledger, and user management are denied in the app and by Apps Script. Admins can use the Users page role tabs to view and add Admin, Collector, and Member accounts, and the **Roles & Permissions** navigation page to configure role-level access. Users → Add/Edit lets authorized account managers upload a JPEG, PNG, or WebP profile image (maximum 300 KB); images are kept in a private Drive folder and are returned only through authenticated portal responses. The Users directory and signed-in profile show the image, with initials as a fallback. Member write permissions are always disabled and rejected by the backend. Admins always retain full access; only Admins can assign roles or edit role settings. App startup displays the centered Flutter splash page; the native Android and iOS launch screens stay plain white so the previous logo splash does not appear before it.

All requests are HTTP `POST` requests with a JSON body and all responses must be JSON. Every operation except `login` and `register` includes the session `token`.

| Action | Request fields | Successful response |
| --- | --- | --- |
| `login` | `email`, `password`, `loginType` (`staff` or `member`) | `{ "status": "success", "token": "...", "user": { "id": "...", "accountNo": "ADM123456789", "name": "...", "profileImageUrl": "data:image/png;base64,...", "email": "...", "role": "Admin" } }`; the backend rejects a mismatch between `loginType` and the account role |
| `register` | `name`, `email`, `password` | `{ "status": "success" }`; new self-registered users must receive the least-privileged role (`Member`) |
| `getAmount` | `token` | JSON array of ledger records; requires shared-data read or ledger-management permission |
| `getDaily`, `getWeekly`, `getMonthly` | `token` | JSON array of collection records; Members always receive only rows whose `memberName` matches their login account name, and must have the corresponding per-account report switch active |
| `getUsers` | `token` | JSON array of `{ "id", "accountNo", "name", "profileImageUrl", "email", "role" }` user records; uploaded images are returned as authenticated data URLs; requires shared-data read or user-management permission |
| `addAmount`, `editAmount`, `deleteAmount` | `token`, plus ledger fields (`date` uses `YYYY-MM-DD`); edit/delete include `rowIndex` | `{ "status": "success" }`; requires ledger-management permission |
| `toggleCollection` | Existing action fields plus `token` | `{ "status": "success" }`; requires collection-management permission |
| `addCollection` | `token`, `sheetName`, `memberName`, `date` (`YYYY-MM-DD`), `depAmt` | `{ "status": "success" }`; requires collection-management permission; appends a collection row with all periods unpaid |
| `editCollection` | `token`, `sheetName`, `rowIndex`, `memberName`, `date`, `depAmt` | `{ "status": "success" }`; requires collection-management permission; updates entry details and recalculates received totals without changing payment marks or `grandTotal` |
| `deleteCollection` | `token`, `sheetName`, `rowIndex` | `{ "status": "success" }`; requires collection-management permission; permanently removes the entry and its payment history |
| `addUser` | `token`, `name`, `email`, `role`, `password`; optional `profileImageData` (base64) and `profileImageMimeType`; Admin may include `dailyAccess`, `weeklyAccess`, and `monthlyAccess` for Members | `{ "status": "success" }` |
| `editUser` | `token`, `userId`, `name`, `email`, `role`; optional `profileImageChanged`, `profileImageData` (base64), and `profileImageMimeType` to update/remove the image; optional `password` to reset it; Admin may update Member report access switches | `{ "status": "success" }` |
| `deleteUser` | `token`, `userId` | `{ "status": "success" }` |
| `changePassword` | `token`, `currentPassword`, `newPassword` | `{ "status": "success" }`; verifies the current password before changing it |
| `getRolePermissions` | Admin `token` | `{ "status": "success", "permissions": { "Collector": { ... }, "Member": { ... } } }`; reads the `Role_Permissions` sheet |
| `setRolePermissions` | Admin `token`, complete `permissions` maps for Collector and Member | `{ "status": "success", "permissions": { ... } }`; updates the `Role_Permissions` sheet and is enforced server-side |

For failures, return `{ "status": "error", "message": "..." }`. Assign each user a stable unique `id`; do not return password hashes in `getUsers` or the login response.

## Role access

Admins always have full access. Admins configure Collector permissions and Member read access from **Roles & Permissions**. Members can be allowed to read shared data and/or their own collections. Admins separately activate or deactivate Daily, Weekly, and Monthly reports for each Member account from the Users editor. Inactive reports are hidden after that Member signs in again and are also blocked by Apps Script. Member collection, ledger, and user management permissions are always false, cannot be enabled in the page, and are forced off by the backend even if a direct API request attempts to enable them. Role-level settings are stored in the Google Sheet's `Role_Permissions` tab; individual report switches are stored on the corresponding `Users` row. Only Admins can assign roles, change role settings, or manage Member report access.

Member collection reports and the Member dashboard are always restricted to rows whose `memberName` matches that account's login `name` (case-insensitive, ignoring surrounding and repeated whitespace), regardless of shared-data role permissions. The dashboard shows the matching Daily, Weekly, and Monthly entries, dates, amounts, and received totals; Member sessions never load the shared ledger or user directory. These names must be unique among active Member accounts. Existing collection rows must use the same name as the corresponding login account; update mismatched names before relying on own-record views. A Member account's unique email and password provide its individual login; public registration creates Member accounts and Admins can create them from the Users → Member tab.

Ledger entry attribution is selected from `1 mafidul`, `2 mohibul`, and `3 Asrsful`.

Each user has a role-specific `accountNo` displayed on the profile and Users directory: Members receive sequential IDs starting with `DRD000000001`, Collectors receive sequential IDs starting with `EMP000000001`, and Admins receive a unique random nine-digit ID prefixed with `ADM`. Internal UUIDs remain unchanged for authentication and user management. Run `setupAccountPortal` after updating the script to add the account number column and migrate existing users to the role-specific format. New users receive an account number automatically.

The profile page displays the account's profile image and allows signed-in users to change a password after verifying the current one. Account managers can upload or remove a profile image from **Users → Add/Edit**. Images are stored privately in Google Drive; only users authorized to view the account directory (and the account owner at login) receive image data. The login page's **Forgot password?** option directs users to contact an administrator, who can reset a password from **Users → Edit → New password**. Passwords are stored as salted hashes and cannot be retrieved or displayed; the eye button only reveals text while entering a new password.

## Install and run the Apps Script backend

1. To keep the supplied account data, use your existing `NTCCSL_ACCOUNT (2).xlsx` workbook. To start with empty sheets, use the [NTCCSL_Account_Portal_Template.xlsx](./NTCCSL_Account_Portal_Template.xlsx) workbook instead.
2. Upload the chosen workbook to Google Drive and open it with Google Sheets. Use **File → Save as Google Sheets** to convert it into a native Google Sheet. An `.xlsx` file cannot host the live Apps Script deployment.
3. Open the converted Google Sheet, then select **Extensions → Apps Script**. This step is important: it creates/opens a script bound to this specific spreadsheet. Do not create a separate project at `script.google.com` for this setup.
4. In that bound Apps Script project, replace the editor contents with [`Code.gs`](./Code.gs) and save.
5. In the Apps Script editor, select `setupAccountPortal` in the function dropdown and click **Run**. Review and approve the requested Google permissions. Wait for the execution to finish successfully. This stores the spreadsheet ID and password secret in this Apps Script project's Script Properties and creates any missing tabs/headers, including the `Role_Permissions` tab and Member report-access columns on `Users`. Existing users with blank report-access cells retain access by default. Existing role settings are preserved except that Member write permissions are forced off. If no saved settings exist, Collector defaults are initialized with all listed permissions enabled and Member defaults to own-collection read-only. When it finds the supplied legacy layout, it imports the ledger and collection records into the portal schema and renames the original tabs with a `_Legacy` suffix (adding a number if needed); the original sheets and their formulas remain available as backups.
6. Return to the Google Sheet and reload it. Confirm these tabs exist: `Users`, `Amount`, `Daily_Collection`, `Weekly_Collection`, and `Monthly_Collection`. The imported workbook already has user records, so use **NTCCSL Portal → Reset admin password** to set a new password for an existing active administrator. Password hashes in an `.xlsx` export cannot be used without the original Apps Script project's secret. If the Users tab is empty, use **NTCCSL Portal → Create first admin** instead. Do not share the sheet or Apps Script editor with ordinary app users.
7. In the **same bound Apps Script project**, choose **Deploy → New deployment → Web app**. Set **Execute as** to your account and **Who has access** to the intended app audience. The app calls the web app as a public endpoint, so access may need to be “Anyone”; in that case, every action is protected by its server-side session-token and role checks. Do not use this deployment with sensitive financial records until you have reviewed the security limitations below.
8. Copy the deployed `/exec` URL and use it in Flutter:

   ```sh
   flutter run --dart-define=GOOGLE_SCRIPT_URL=https://script.google.com/macros/s/DEPLOYMENT_ID/exec
   ```

9. After changing the Apps Script, create a new deployment version or update the existing deployment. Saving the editor alone does not update an already deployed version. The first role-permissions request creates the `Role_Permissions` tab and initializes it if it is missing; alternatively, run `setupAccountPortal` in the bound project. Confirm the tab contains one row for `Collector` and one for `Member`.
10. Sign in with the administrator whose password you set in step 6. Public self-registration creates a `Member`, not an admin. Admins can view and manage ledger and collection data; Collectors can view shared records but cannot change them; Members see only matching personal collection rows and cannot change them. Admins can manage user accounts and add collectors using the Users page.

### Fix: “Spreadsheet is not configured”

This means the deployed script project has no `SPREADSHEET_ID` in its Script Properties. Run `setupAccountPortal` from the **Apps Script project opened through the target Google Sheet** (steps 3–5 above). Running setup in another or standalone Apps Script project will not configure the deployed web app: Script Properties belong to one script project and are not shared between projects.

After setup succeeds, confirm the web app deployment was created from that same bound project. If you accidentally deployed another Apps Script project, deploy this bound project and replace Flutter's `GOOGLE_SCRIPT_URL` with its `/exec` URL. The Flutter request itself cannot initialize the spreadsheet; setup is a one-time owner action.

Collection tabs use the headers created by setup (`memberName`, `date`, `depAmt`, totals, and `P1...Pn`). Admins and collectors can use the Add entry form on each Daily, Weekly, or Monthly page; the backend validates the selected sheet and initializes all payment periods as unpaid. The Amount tab uses the headers created by setup.

`grandTotal` is displayed as red, read-only information in collection entries. It is not included in add/edit requests and is preserved when an entry is edited. Deleting a collection entry still deletes that entire record, including its associated payment history.

## Security and verification notes

Passwords are never stored in plaintext. This Apps Script implementation uses a per-user salt and an HMAC-SHA-256 digest keyed by a random secret stored in Script Properties, along with expiring server-side session tokens and role checks on every protected action. This is a lightweight Google Apps Script implementation, **not a 100% security guarantee or a substitute for a dedicated identity provider**. Apps Script does not provide a built-in memory-hard password hashing API; for sensitive production financial data, use Firebase Authentication or another established identity provider and a backend designed for that security requirement. Limit Apps Script editor access, keep the spreadsheet private, and protect a web app accessible to “Anyone” with strong credentials and monitoring.

The last active administrator cannot be demoted or deleted. Script-side errors are returned as `{ "status": "error", "message": "..." }`; the Flutter UI must not be treated as an authorization boundary. Never type passwords or password hashes into the Users sheet; account creation and password hashing happen through Apps Script actions.

Local tests verify Flutter UI behavior and the client/server JSON contract with simulated responses. They cannot verify deployment permissions, Google Sheets contents, Apps Script quotas, or real credentials. Complete the live sign-in, registration, role-denial, and CRUD smoke tests after deploying to your own spreadsheet.

The login session is kept in memory and is discarded when the user signs out or closes the app. Configure `GOOGLE_SCRIPT_URL` to point to a deployment of the current `Code.gs`; an older deployment may not support the current login and registration actions. Local widget tests verify the UI and expected API contract; they do not prove that the deployed Apps Script or production credentials work.

The app has a default endpoint in `lib/main.dart`. To use another deployment URL, pass it at run/build time:

```sh
flutter run --dart-define=GOOGLE_SCRIPT_URL=https://script.google.com/macros/s/DEPLOYMENT_ID/exec
```

If the endpoint returns HTML, an error page, or a response with an unexpected JSON shape, the affected screen displays the service error and a retry button rather than showing a misleading empty list.
