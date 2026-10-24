CREATE TABLE `daily_cache` (
	`key` text PRIMARY KEY NOT NULL,
	`content` text NOT NULL,
	`source` text NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `events` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`product` text,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `expenses` (
	`id` text PRIMARY KEY NOT NULL,
	`category` text NOT NULL,
	`amount` integer NOT NULL,
	`date` text NOT NULL,
	`note` text NOT NULL,
	`created_at` text NOT NULL,
	`request_key` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `expenses_request_key_unique` ON `expenses` (`request_key`);--> statement-breakpoint
CREATE TABLE `orders` (
	`id` text PRIMARY KEY NOT NULL,
	`owner_id` text NOT NULL,
	`request_key` text NOT NULL,
	`fingerprint` text NOT NULL,
	`product` text NOT NULL,
	`amount` integer NOT NULL,
	`discount` integer DEFAULT 0 NOT NULL,
	`currency` text DEFAULT 'PYG' NOT NULL,
	`payload` text NOT NULL,
	`payment_status` text DEFAULT 'pending' NOT NULL,
	`delivery_status` text DEFAULT 'pending' NOT NULL,
	`result` text,
	`source` text,
	`ai_cost` real DEFAULT 0 NOT NULL,
	`fee_estimate` real DEFAULT 0 NOT NULL,
	`referral_owner` text,
	`marketing_consent` integer DEFAULT 0 NOT NULL,
	`consent_version` text NOT NULL,
	`created_at` text NOT NULL,
	`paid_at` text,
	`delivered_at` text,
	`lease_until` text,
	`attempts` integer DEFAULT 0 NOT NULL,
	`error_code` text,
	`mode` text DEFAULT 'demo' NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `orders_request` ON `orders` (`owner_id`,`request_key`);--> statement-breakpoint
CREATE INDEX `orders_owner` ON `orders` (`owner_id`,`created_at`);--> statement-breakpoint
CREATE INDEX `orders_paid` ON `orders` (`paid_at`);--> statement-breakpoint
CREATE TABLE `payment_events` (
	`id` text PRIMARY KEY NOT NULL,
	`order_id` text NOT NULL,
	`state` text NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `profiles` (
	`id` text PRIMARY KEY NOT NULL,
	`referral_code` text NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `profiles_referral_code_unique` ON `profiles` (`referral_code`);--> statement-breakpoint
CREATE TABLE `rate_limits` (
	`key` text PRIMARY KEY NOT NULL,
	`count` integer NOT NULL,
	`expires_at` integer NOT NULL
);
