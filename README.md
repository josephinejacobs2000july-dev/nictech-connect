# nictech-connect

Nictech International service app: book services and maintenance contracts, track jobs, and post daily work logs.

Live app: https://josephinejacobs2000july-dev.github.io/nictech-connect/

## What's inside
- `index.html` – the whole app (Home, Book, My requests, Daily work, Office, Account)
- `manifest.json`, `sw.js`, `icon.svg` – make it installable on phones and work offline
- `database/supabase-setup.sql` – creates the Supabase tables and security rules (run once in the Supabase SQL Editor)
- `database/all-updates.sql` – everything below in one file; safe to run more than once (recommended)
- `database/security-update-1.sql` – extra protections: size limits, a daily booking limit, and locked office fields (run once, after the setup file)
- `database/update-2-portal.sql` – invoice amount, currency and payment status on each job (run once, after security update 1)
- `database/update-3-photos.sql` – private photo storage for technicians' work photos (run once, after update 2)

## Who can do what
| Access | Can |
|---|---|
| Client (everyone who signs up) | Book services, request contracts, follow their own jobs, rate finished work |
| Technician | Post daily work, see all jobs and the full work log |
| Office | Everything above, plus review, schedule and assign requests and change people's access |

The office changes someone's access on the Office tab, under "People and access".
