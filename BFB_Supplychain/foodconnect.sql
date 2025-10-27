PRAGMA foreign_keys = ON;

-- Drop existing tables
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS requests;
DROP TABLE IF EXISTS food_items;
DROP TABLE IF EXISTS user_roles;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS locations;

-- LOCATIONS
CREATE TABLE locations (
    location_id INTEGER PRIMARY KEY AUTOINCREMENT,
    province TEXT NOT NULL,
    city TEXT NOT NULL,
    zip_code TEXT NOT NULL,
    street_address TEXT NOT NULL
);

-- USERS
CREATE TABLE users (
    user_id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_fullname TEXT NOT NULL,
    occupation TEXT CHECK (occupation IN ('Restaurant', 'Grocery Store', 'Farm', 'Bakery', 'Manufacturer', 'Other', '')),
    location_id INTEGER NOT NULL REFERENCES locations(location_id) ON DELETE RESTRICT,
    contact_number TEXT NOT NULL CHECK (contact_number GLOB '[0-9]*' OR contact_number GLOB '+[0-9]*'),
    email TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- USER ROLES
CREATE TABLE user_roles (
    user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('Supplier', 'Recipient')),
    PRIMARY KEY (user_id, role)
);

-- FOOD ITEMS (Surplus uploaded by Suppliers)
CREATE TABLE food_items (
    item_id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    food_type TEXT NOT NULL CHECK (food_type IN ('Vegetables', 'Fruits', 'Dairy', 'Bakery', 'Meat', 'Grains', 'Beverages', 'Other')),
    food_name TEXT NOT NULL,
    quantity_available NUMERIC(10,2) NOT NULL,
    expiry_date DATE NOT NULL, 
    delivery_option TEXT NOT NULL CHECK (delivery_option IN ('Pickup', 'Delivery')),
    location_id INTEGER NOT NULL REFERENCES locations(location_id) ON DELETE RESTRICT,
    description TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    status TEXT NOT NULL CHECK (status IN ('Unselected', 'Pending', 'Selected', 'Completed')) DEFAULT 'Unselected'
);

-- REQUESTS (Created by Recipients)
CREATE TABLE requests (
    request_id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER NOT NULL REFERENCES food_items(item_id) ON DELETE CASCADE,
    recipient_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    quantity_needed NUMERIC(10,2) NOT NULL,
    urgency_level TEXT CHECK (urgency_level IN ('Low', 'Medium', 'High')) DEFAULT 'Medium',
    status TEXT NOT NULL CHECK (status IN ('Pending', 'Selected', 'Completed', 'Cancelled')) DEFAULT 'Pending',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- TRANSACTIONS (Donation flow - optional for dashboard)
CREATE TABLE transactions (
    transaction_id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER NOT NULL UNIQUE REFERENCES food_items(item_id) ON DELETE CASCADE,
    supplier_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    recipient_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    quantity NUMERIC(10,2) NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('In-Progress', 'Completed')) DEFAULT 'In-Progress',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- TRIGGERS
CREATE TRIGGER sync_food_item_status
AFTER UPDATE OF status ON requests
FOR EACH ROW
WHEN NEW.status IN ('Selected', 'Cancelled')
BEGIN
    UPDATE food_items
    SET status = CASE
        WHEN NEW.status = 'Selected' AND food_items.status = 'Unselected' THEN 'Pending'
        WHEN NEW.status = 'Cancelled' AND food_items.status = 'Pending' THEN 'Unselected'
        ELSE food_items.status
    END
    WHERE item_id = NEW.item_id;
END;

CREATE TRIGGER validate_transaction
BEFORE INSERT ON transactions
FOR EACH ROW
BEGIN
    SELECT RAISE(ABORT, 'Invalid supplier or recipient')
    WHERE NEW.supplier_id != (SELECT user_id FROM food_items WHERE item_id = NEW.item_id)
    OR NEW.recipient_id != (SELECT recipient_id FROM requests WHERE item_id = NEW.item_id AND status = 'Selected')
    OR NOT EXISTS (SELECT 1 FROM user_roles WHERE user_id = NEW.supplier_id AND role = 'Supplier')
    OR NOT EXISTS (SELECT 1 FROM user_roles WHERE user_id = NEW.recipient_id AND role = 'Recipient');
END;

CREATE TRIGGER validate_request_quantity
BEFORE INSERT ON requests
FOR EACH ROW
BEGIN
    SELECT RAISE(ABORT, 'Quantity needed exceeds available')
    WHERE NEW.quantity_needed > (SELECT quantity_available FROM food_items WHERE item_id = NEW.item_id);
END;

CREATE TRIGGER validate_transaction_quantity
BEFORE INSERT ON transactions
FOR EACH ROW
BEGIN
    SELECT RAISE(ABORT, 'Transaction quantity exceeds available')
    WHERE NEW.quantity > (SELECT quantity_available FROM food_items WHERE item_id = NEW.item_id);
END;

-- INDEXES
CREATE INDEX idx_food_items_status ON food_items(status);
CREATE INDEX idx_food_items_user_id ON food_items(user_id);
CREATE INDEX idx_requests_item_id ON requests(item_id);
CREATE INDEX idx_requests_recipient_id ON requests(recipient_id);
CREATE INDEX idx_transactions_item_id ON transactions(item_id);
CREATE INDEX idx_user_roles_user_id ON user_roles(user_id);

-- MOCK DATA
INSERT INTO locations (province, city, zip_code, street_address) VALUES
('Western Cape', 'Cape Town', '8001', '123 Long Street'),
('Gauteng', 'Johannesburg', '2001', '456 Main Road'),
('KwaZulu-Natal', 'Durban', '4001', '789 Beachfront Avenue');

INSERT INTO users (user_fullname, occupation, location_id, contact_number, email, password, created_at) VALUES
('Alice Smith', 'Restaurant', 1, '0631234567', 'alice@example.com', 'hashed_password_1', '2025-10-27 10:00:00'),
('Bob Johnson', 'Grocery Store', 2, '+27712345678', 'bob@example.com', 'hashed_password_2', '2025-10-27 10:05:00'),
('Carol White', '', 3, '0823456789', 'carol@example.com', 'hashed_password_3', '2025-10-27 10:10:00'),
('David Brown', 'Bakery', 1, '+27609876543', 'david@example.com', 'hashed_password_4', '2025-10-27 10:15:00');

INSERT INTO user_roles (user_id, role) VALUES
(1, 'Supplier'),
(1, 'Recipient'),
(2, 'Supplier'),
(3, 'Recipient'),
(4, 'Supplier'),
(4, 'Recipient');

INSERT INTO food_items (user_id, food_type, food_name, quantity_available, expiry_date, delivery_option, location_id, description, created_at, status) VALUES
(1, 'Vegetables', 'Carrots', 10.0, '2025-11-15', 'Pickup', 1, 'Fresh carrots', '2025-10-27 10:20:00', 'Unselected'),
(1, 'Fruits', 'Apples', 8.0, '2025-11-10', 'Delivery', 1, 'Locally grown apples', '2025-10-27 10:25:00', 'Pending'),
(2, 'Grains', 'Rice', 20.0, '2026-01-01', 'Pickup', 2, '2kg rice bags, sealed', '2025-10-27 10:30:00', 'Selected'),
(4, 'Bakery', 'Bread', 6.0, '2025-11-05', 'Delivery', 1, 'Freshly baked loaves', '2025-10-27 10:35:00', 'Unselected');

--Request only references existing food_items
INSERT INTO requests (item_id, recipient_id, quantity_needed, status, created_at) VALUES
(2, 4, 5.0, 'Pending', '2025-10-27 10:40:00'),
(3, 3, 10.0, 'Selected', '2025-10-27 10:45:00');

