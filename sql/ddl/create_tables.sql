USE upi_payments;
GO

-- =============================================
-- LAYER 1: No dependencies
-- =============================================

CREATE TABLE bank (
    bank_id       VARCHAR(36) PRIMARY KEY,
    bank_name     VARCHAR(100) NOT NULL,
    ifsc_code     VARCHAR(11) NOT NULL UNIQUE
);
GO

CREATE TABLE merchant_category (
    merchant_category_id    VARCHAR(36) PRIMARY KEY,
    merchant_category_name  VARCHAR(100) NOT NULL,
    mcc_code                VARCHAR(4) NOT NULL UNIQUE
);
GO

-- =============================================
-- LAYER 2: Depends on Layer 1
-- =============================================

CREATE TABLE [user] (
    user_surrogate_key   VARCHAR(36) PRIMARY KEY,
    user_id              VARCHAR(36) NOT NULL,
    first_name           VARCHAR(50) NOT NULL,
    last_name            VARCHAR(50) NOT NULL,
    phone_number         VARCHAR(15) NOT NULL,
    email                VARCHAR(100) NOT NULL,
    upi_id               VARCHAR(50) NOT NULL,
    effective_start_date DATETIME NOT NULL,
    effective_end_date   DATETIME NULL,
    is_active            BIT NOT NULL
);
GO

CREATE TABLE merchant (
    merchant_surrogate_key  VARCHAR(36) PRIMARY KEY,
    merchant_id             VARCHAR(36) NOT NULL,
    business_name           VARCHAR(100) NOT NULL,
    business_phone_number   VARCHAR(15) NOT NULL,
    email                   VARCHAR(100) NOT NULL,
    upi_id                  VARCHAR(50) NOT NULL,
    merchant_type           VARCHAR(20) NOT NULL,
    merchant_category_id    VARCHAR(36) NOT NULL,
    effective_start_date    DATETIME NOT NULL,
    effective_end_date      DATETIME NULL,
    is_active               BIT NOT NULL,
    CONSTRAINT fk_merchant_category
        FOREIGN KEY (merchant_category_id)
        REFERENCES merchant_category(merchant_category_id),
    CONSTRAINT chk_merchant_type
        CHECK (merchant_type IN (
            'INDIVIDUAL','SMALL_BUSINESS','ENTERPRISE','OFFLINE'
        ))
);
GO

-- =============================================
-- LAYER 3: Depends on Layer 2
-- =============================================

CREATE TABLE payment_method (
    payment_method_id    VARCHAR(36) PRIMARY KEY,
    user_id              VARCHAR(36) NOT NULL,
    bank_id              VARCHAR(36) NOT NULL,
    payment_method_type  VARCHAR(20) NOT NULL,
    account_number       VARCHAR(20) NOT NULL,
    ifsc_code            VARCHAR(11) NOT NULL,
    CONSTRAINT fk_payment_method_bank
        FOREIGN KEY (bank_id) REFERENCES bank(bank_id),
    CONSTRAINT chk_payment_method_type
        CHECK (payment_method_type IN (
            'SAVINGS_ACCOUNT','CURRENT_ACCOUNT',
            'CREDIT_CARD','PREPAID_WALLET'
        ))
);
GO

CREATE NONCLUSTERED INDEX idx_payment_method_user_id
    ON payment_method(user_id);
CREATE NONCLUSTERED INDEX idx_payment_method_bank_id
    ON payment_method(bank_id);
GO

-- =============================================
-- LAYER 4: Depends on Layer 3
-- =============================================

CREATE TABLE [transaction] (
    trans_id                VARCHAR(36) PRIMARY KEY,
    user_id                 VARCHAR(36) NOT NULL,
    merchant_id             VARCHAR(36) NOT NULL,
    sender_bank_id          VARCHAR(36) NOT NULL,
    receiver_bank_id        VARCHAR(36) NOT NULL,
    upi_reference_id        VARCHAR(50) NOT NULL UNIQUE,
    transaction_amount      DECIMAL(18,2) NOT NULL,
    platform_fee            DECIMAL(18,2) NOT NULL,
    merchant_payout_amount  DECIMAL(18,2) NOT NULL,
    initiated_at            DATETIME NOT NULL,
    completed_at            DATETIME NULL,
    CONSTRAINT fk_transaction_sender_bank
        FOREIGN KEY (sender_bank_id) REFERENCES bank(bank_id),
    CONSTRAINT fk_transaction_receiver_bank
        FOREIGN KEY (receiver_bank_id) REFERENCES bank(bank_id)
);
GO

CREATE NONCLUSTERED INDEX idx_transaction_user_id
    ON [transaction](user_id);
CREATE NONCLUSTERED INDEX idx_transaction_merchant_id
    ON [transaction](merchant_id);
GO

-- =============================================
-- LAYER 5: Depends on Layer 4
-- =============================================

CREATE TABLE transaction_status (
    status_id        VARCHAR(36) PRIMARY KEY,
    trans_id         VARCHAR(36) NOT NULL,
    status           VARCHAR(20) NOT NULL,
    status_timestamp DATETIME NOT NULL,
    CONSTRAINT fk_transaction_status
        FOREIGN KEY (trans_id)
        REFERENCES [transaction](trans_id),
    CONSTRAINT chk_transaction_status
        CHECK (status IN (
            'PENDING','PROCESSING','SUCCESS',
            'FAILED','RETRIED','REVERSED','EXPIRED'
        ))
);
GO

CREATE NONCLUSTERED INDEX idx_transaction_status_trans_id
    ON transaction_status(trans_id);
GO

CREATE TABLE settlement_batch (
    settlement_batch_surrogate_key  VARCHAR(36) PRIMARY KEY,
    settlement_batch_id             VARCHAR(50) NOT NULL UNIQUE,
    batch_date                      DATETIME NOT NULL,
    total_amount                    DECIMAL(18,2) NOT NULL,
    batch_status                    VARCHAR(20) NOT NULL,
    created_at                      DATETIME NOT NULL,
    settled_at                      DATETIME NULL,
    CONSTRAINT chk_batch_status
        CHECK (batch_status IN (
            'PENDING','PROCESSING','SUCCESS','FAILED','REVERSED'
        ))
);
GO

CREATE TABLE fraud_signal (
    fraud_signal_id   VARCHAR(36) PRIMARY KEY,
    trans_id          VARCHAR(36) NOT NULL,
    user_id           VARCHAR(36) NOT NULL,
    signal_type       VARCHAR(50) NOT NULL,
    risk_score        DECIMAL(5,2) NOT NULL,
    flagged_at        DATETIME NOT NULL,
    reviewed_at       DATETIME NULL,
    resolution_status VARCHAR(20) NOT NULL,
    notes             VARCHAR(500) NULL,
    CONSTRAINT fk_fraud_signal_transaction
        FOREIGN KEY (trans_id)
        REFERENCES [transaction](trans_id),
    CONSTRAINT chk_resolution_status
        CHECK (resolution_status IN (
            'OPEN','UNDER_REVIEW','RESOLVED','FALSE_POSITIVE'
        )),
    CONSTRAINT chk_signal_type
        CHECK (signal_type IN (
            'DUPLICATE_TRANSACTION','UNUSUAL_AMOUNT',
            'HIGH_FREQUENCY','SUSPICIOUS_MERCHANT','BLACKLISTED_USER'
        ))
);
GO

CREATE NONCLUSTERED INDEX idx_fraud_signal_trans_id
    ON fraud_signal(trans_id);
CREATE NONCLUSTERED INDEX idx_fraud_signal_user_id
    ON fraud_signal(user_id);
GO

-- =============================================
-- LAYER 6: Depends on Layer 5
-- =============================================

CREATE TABLE settlement (
    settlement_id       VARCHAR(36) PRIMARY KEY,
    trans_id            VARCHAR(36) NOT NULL,
    settlement_batch_id VARCHAR(36) NOT NULL,
    settled_amount      DECIMAL(18,2) NOT NULL,
    settlement_status   VARCHAR(20) NOT NULL,
    settled_at          DATETIME NULL,
    CONSTRAINT fk_settlement_transaction
        FOREIGN KEY (trans_id)
        REFERENCES [transaction](trans_id),
    CONSTRAINT fk_settlement_batch
        FOREIGN KEY (settlement_batch_id)
        REFERENCES settlement_batch(settlement_batch_surrogate_key),
    CONSTRAINT chk_settlement_status
        CHECK (settlement_status IN (
            'PENDING','PROCESSING','SUCCESS','FAILED','REVERSED'
        ))
);
GO

CREATE NONCLUSTERED INDEX idx_settlement_trans_id
    ON settlement(trans_id);
CREATE NONCLUSTERED INDEX idx_settlement_batch_id
    ON settlement(settlement_batch_id);
GO

CREATE TABLE audit_log (
    audit_log_id  VARCHAR(36) PRIMARY KEY,
    entity_type   VARCHAR(50) NOT NULL,
    entity_id     VARCHAR(36) NOT NULL,
    action        VARCHAR(20) NOT NULL,
    changed_by    VARCHAR(100) NOT NULL,
    changed_at    DATETIME NOT NULL,
    old_value     VARCHAR(MAX) NULL,
    new_value     VARCHAR(MAX) NULL,
    CONSTRAINT chk_action
        CHECK (action IN (
            'INSERT','UPDATE','DELETE','STATUS_CHANGE'
        ))
);
GO

CREATE NONCLUSTERED INDEX idx_audit_log_entity_id
    ON audit_log(entity_id);
GO