# greggesmart

## Collegare l'app a Supabase (guida passo passo)

Questa guida e' pensata per chi usa Supabase per la prima volta.

### 1) Crea progetto su Supabase

1. Vai su https://supabase.com/dashboard
2. Clicca **New project**
3. Scegli Organization, nome progetto e password database
4. Aspetta che il progetto sia pronto (1-2 minuti)

### 2) Crea tabelle cloud

1. Nel progetto Supabase, apri **SQL Editor**
2. Clicca **New query**
3. Copia tutto il contenuto di `supabase/schema.sql`
4. Esegui la query con **Run**

### 3) Recupera URL e anon key

1. Apri **Project Settings -> API**
2. Copia:
	- `Project URL`
	- `anon public key`

### 4) Inserisci credenziali nell'app Flutter

1. Apri `lib/supabase/supabase_config.dart`
2. Compila:

```dart
static const String url = 'https://TUO-PROGETTO.supabase.co';
static const String anonKey = 'TUO_ANON_KEY';
```

### 5) Installa dipendenze

Esegui:

```bash
flutter pub get
```

### 6) Test connessione da app

1. Avvia l'app
2. Apri **Impostazioni**
3. Sezione **SUPABASE**
4. Premi **TEST CONNESSIONE**
5. Se tutto e' corretto vedrai `Connessione Supabase OK`

### 7) Primo sync dei dati

1. In **Impostazioni**, premi **SYNC ORA**
2. L'app carica su Supabase:
	- pecore
	- master
	- storico
	- configurazione
3. In Supabase controlla in **Table Editor** le tabelle `app_pecore`, `app_master`, `app_storico`, `app_configurazione`

## Note importanti

- Questa prima integrazione usa policy RLS aperte (`using true`) per semplificare l'avvio.
- Prima di andare in produzione conviene aggiungere autenticazione utenti e policy RLS per utente/tenant.
- L'app crea un `tenant_id` locale automatico al primo sync e lo salva in configurazione.
