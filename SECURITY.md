# Rosemary's Wear House: Security Guide
For the owner, the developer (admin) and anyone who looks after this system. Read it once, then use the checklists.

## 1. How the system protects the business
| Layer | Protection |
|---|---|
| In transit | All traffic is HTTPS (Vercel and Supabase). Security headers force HTTPS, block framing, block plugins, and restrict which sites the app may talk to. |
| Sign-in | Individual accounts, no public sign-up, new accounts start inactive, login throttling, 12-character passwords, optional authenticator-app two-step sign-in, 30-minute inactivity sign-out. |
| Data access | The database itself decides who sees what (Row Level Security). The public key can read nothing. Staff never see costs or profit. |
| Money integrity | Sales history cannot be edited or deleted through the app. Staff cannot sell below the authorised price, cannot give themselves discounts, cannot confirm more pieces than were shipped. |
| Accountability | Every price, discount, stock confirmation, role, rate, batch and setting change, plus sign-ins, exports and imports, is written to an activity log that nobody can edit from the app. |
| Code | No secrets in the code (the "anon" key is public by design). Third-party libraries are version-pinned and can be hosted from your own site. |

## 2. One-time setup (in this order)
1. Run `supabase/09_security.sql` (after 01-08). Then run the app update (version 2.7).
2. **Supabase → Authentication:** public sign-ups OFF; minimum password length 12 or more; TOTP multi-factor ON; Site URL and Redirect URLs set to your Vercel address only; unused sign-in providers OFF. Names of settings change over time, so look for the nearest match.
3. **Supabase → Project Settings:** turn on SSL enforcement for database connections if offered. Consider reducing the JWT expiry to 1800 seconds or less.
4. **Turn on two-step sign-in** for the owner and the admin (Security tab). Sign out and back in with a code to test it.
5. **Optional enforcement:** once BOTH have tested it, run `supabase/10_require_mfa.sql`. Owner and admin powers then require a verified code. The emergency switch-off line is in that file.
6. **Your own accounts:** two-step sign-in on GitHub, Vercel and Supabase; a password manager; a different password for each.
7. **GitHub:** repository Private; secret scanning and push protection ON; protect the `main` branch against force pushes. Never commit exported Excel files (`.gitignore` already blocks them) or any `service_role` key.
8. **Optional supply-chain hardening:** run `sh tools/vendor.sh`, add `export const VENDORED = true;` to `config.js`, push, then remove `https://cdn.jsdelivr.net` from `script-src` in `vercel.json` and `index.html`. Tighten `connect-src` from `https://*.supabase.co` to your exact project address.

## 3. Routines
| When | What |
|---|---|
| Weekly (owner) | Read the Activity log (Security tab). Look for discounts, price changes, receipts or sign-ins you do not recognise. |
| Weekly | Sign in so the free database does not pause. |
| Monthly | Export to Excel (Data tab); keep a copy offline. Once a quarter, open the file to check it is complete. |
| Monthly (admin) | Users tab: is every active account a person who still works here? Deactivate leavers the same day. |
| After a staff member leaves | Untick Active; in Supabase Authentication, ban or delete the user; change any shared passwords. |

## 4. If something goes wrong
- **Lost or stolen phone or laptop:** change that person's password in Supabase (Authentication → Users); untick Active in the Users tab until it is sorted; if the owner's phone holds the authenticator app, the admin can remove the factor in Supabase.
- **Suspected account misuse:** deactivate the account; read the Activity log; change the password; check whether sales or stock look wrong.
- **Suspected data leak:** reset passwords for everyone; in Supabase, rotate the JWT secret (this signs everyone out); tell the owner; keep the log and screenshots.
- **Lost owner and admin phones at the same time:** the Supabase account owner can run `update settings set value='off' where key='require_mfa';` in the SQL Editor.
- **Mistake in the data:** tell the developer. Corrections are made in the database and are recorded in the log.

## 5. Personal data
The app keeps customer names (optional) and staff names and emails. Nigeria's Data Protection Act 2023 expects you to collect only what you need, keep it safe, and not keep it longer than necessary. Do not type customers' phone numbers or addresses into the customer field. Ask a Nigerian lawyer whether the business needs to register with the NDPC. This is guidance, not legal advice.

## 6. What this does not cover (residual risks)
- Login tokens live in the browser's storage, as with any app without its own server. A strict content policy, no third-party scripts you do not choose, and the inactivity sign-out reduce the risk. Do not install unknown browser extensions on the store computer.
- The free plans have no point-in-time recovery, short log retention, no firewall and no server-enforced inactivity timeout. Monthly exports are your safety net.
- Someone with both the owner's password and phone can see everything. Two-step sign-in and a PIN-locked phone are the answer.
- Staff can still make mistakes or collude within their permissions (for example, selling a real item at the authorised price and keeping the cash). The Activity log, stock counts and receipt numbers are your detection tools.
