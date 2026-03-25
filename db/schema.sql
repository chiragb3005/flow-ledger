-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ======================
-- 1. USERS
-- ======================
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ======================
-- 2. ACCOUNTS
-- ======================
CREATE TABLE accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('asset', 'expense', 'income')),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ======================
-- 3. TRANSACTIONS
-- ======================
CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ======================
-- 4. LEDGER ENTRIES (CORE)
-- ======================
CREATE TABLE ledger_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id UUID NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    amount NUMERIC(19,4) NOT NULL CHECK (amount > 0),
    entry_type TEXT NOT NULL CHECK (entry_type IN ('debit', 'credit')),
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE OR REPLACE FUNCTION validate_transaction_balance()
RETURNS TRIGGER AS $$
DECLARE
    debit_sum NUMERIC;
    credit_sum NUMERIC;
BEGIN
    SELECT 
        COALESCE(SUM(CASE WHEN entry_type = 'debit' THEN amount END), 0),
        COALESCE(SUM(CASE WHEN entry_type = 'credit' THEN amount END), 0)
    INTO debit_sum, credit_sum
    FROM ledger_entries
    WHERE transaction_id = NEW.transaction_id;

    IF debit_sum <> credit_sum THEN
        RAISE EXCEPTION 'Transaction not balanced: debit % != credit %', debit_sum, credit_sum;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- CREATE OR REPLACE FUNCTION validate_transaction_balance()
RETURNS TRIGGER AS $$
DECLARE
    debit_sum NUMERIC;
    credit_sum NUMERIC;
BEGIN
    SELECT 
        COALESCE(SUM(CASE WHEN entry_type = 'debit' THEN amount END), 0),
        COALESCE(SUM(CASE WHEN entry_type = 'credit' THEN amount END), 0)
    INTO debit_sum, credit_sum
    FROM ledger_entries
    WHERE transaction_id = NEW.transaction_id;

    IF debit_sum <> credit_sum THEN
        RAISE EXCEPTION 'Transaction not balanced: debit % != credit %', debit_sum, credit_sum;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_simple_transaction(
    p_user_id UUID,
    p_amount NUMERIC,
    p_description TEXT,
    p_debit_account UUID,
    p_credit_account UUID
)
RETURNS VOID AS $$
DECLARE
    tx_id UUID;
BEGIN
    INSERT INTO transactions (user_id, description)
    VALUES (p_user_id, p_description)
    RETURNING id INTO tx_id;

    INSERT INTO ledger_entries (transaction_id, account_id, amount, entry_type)
    VALUES (tx_id, p_debit_account, p_amount, 'debit');

    INSERT INTO ledger_entries (transaction_id, account_id, amount, entry_type)
    VALUES (tx_id, p_credit_account, p_amount, 'credit');
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_transaction_balance
AFTER INSERT OR UPDATE ON ledger_entries
FOR EACH ROW
EXECUTE FUNCTION validate_transaction_balance();

DROP TRIGGER IF EXISTS check_transaction_balance ON ledger_entries;