import { sqliteTable, text, integer, real, uniqueIndex, index } from "drizzle-orm/sqlite-core";
export const profiles = sqliteTable("profiles", {id:text("id").primaryKey(),referralCode:text("referral_code").notNull().unique(),createdAt:text("created_at").notNull()});
export const orders = sqliteTable("orders", {
 id:text("id").primaryKey(), ownerId:text("owner_id").notNull(), requestKey:text("request_key").notNull(),fingerprint:text("fingerprint").notNull(),
 product:text("product").notNull(),amount:integer("amount").notNull(),discount:integer("discount").notNull().default(0),currency:text("currency").notNull().default("PYG"),
 payload:text("payload").notNull(),paymentStatus:text("payment_status").notNull().default("pending"),deliveryStatus:text("delivery_status").notNull().default("pending"),
 result:text("result"),source:text("source"),aiCost:real("ai_cost").notNull().default(0),feeEstimate:real("fee_estimate").notNull().default(0),referralOwner:text("referral_owner"),
 marketingConsent:integer("marketing_consent").notNull().default(0),consentVersion:text("consent_version").notNull(),createdAt:text("created_at").notNull(),
 paidAt:text("paid_at"),deliveredAt:text("delivered_at"),leaseUntil:text("lease_until"),attempts:integer("attempts").notNull().default(0),errorCode:text("error_code"),mode:text("mode").notNull().default("demo"),
},t=>[uniqueIndex("orders_request").on(t.ownerId,t.requestKey),index("orders_owner").on(t.ownerId,t.createdAt),index("orders_paid").on(t.paidAt)]);
export const paymentEvents=sqliteTable("payment_events",{id:text("id").primaryKey(),orderId:text("order_id").notNull(),state:text("state").notNull(),createdAt:text("created_at").notNull()});
export const dailyCache=sqliteTable("daily_cache",{key:text("key").primaryKey(),content:text("content").notNull(),source:text("source").notNull(),createdAt:text("created_at").notNull()});
export const expenses=sqliteTable("expenses",{id:text("id").primaryKey(),category:text("category").notNull(),amount:integer("amount").notNull(),date:text("date").notNull(),note:text("note").notNull(),createdAt:text("created_at").notNull(),requestKey:text("request_key").notNull().unique()});
export const events=sqliteTable("events",{id:text("id").primaryKey(),name:text("name").notNull(),product:text("product"),createdAt:text("created_at").notNull()});
export const rateLimits=sqliteTable("rate_limits",{key:text("key").primaryKey(),count:integer("count").notNull(),expiresAt:integer("expires_at").notNull()});

export const qrCodes=sqliteTable("qr_codes",{
 slot:integer("slot").primaryKey(),id:text("id").notNull().unique(),objectKey:text("object_key").notNull(),mime:text("mime").notNull(),
 holder:text("holder").notNull(),label:text("label").notNull(),amount:integer("amount").notNull(),generatedAt:text("generated_at").notNull(),expiresAt:text("expires_at").notNull(),
 enabled:integer("enabled").notNull().default(1),reusable:integer("reusable").notNull().default(0),updatedAt:text("updated_at").notNull(),
});
export const qrIntents=sqliteTable("qr_intents",{
 orderId:text("order_id").primaryKey(),qrId:text("qr_id").notNull(),snapshot:text("snapshot").notNull(),createdAt:text("created_at").notNull(),
});
export const manualPayments=sqliteTable("manual_payments",{
 orderId:text("order_id").primaryKey(),payer:text("payer").notNull(),reference:text("reference").notNull(),reportedAt:text("reported_at").notNull(),
 status:text("status").notNull().default("review"),transactionKey:text("transaction_key").unique(),verifiedAt:text("verified_at"),verifiedBy:text("verified_by"),note:text("note"),
});
