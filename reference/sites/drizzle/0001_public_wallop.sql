CREATE TABLE `manual_payments` (
	`order_id` text PRIMARY KEY NOT NULL,
	`payer` text NOT NULL,
	`reference` text NOT NULL,
	`reported_at` text NOT NULL,
	`status` text DEFAULT 'review' NOT NULL,
	`transaction_key` text,
	`verified_at` text,
	`verified_by` text,
	`note` text
);
--> statement-breakpoint
CREATE UNIQUE INDEX `manual_payments_transaction_key_unique` ON `manual_payments` (`transaction_key`);--> statement-breakpoint
CREATE TABLE `qr_codes` (
	`slot` integer PRIMARY KEY NOT NULL,
	`id` text NOT NULL,
	`object_key` text NOT NULL,
	`mime` text NOT NULL,
	`holder` text NOT NULL,
	`label` text NOT NULL,
	`amount` integer NOT NULL,
	`generated_at` text NOT NULL,
	`expires_at` text NOT NULL,
	`enabled` integer DEFAULT 1 NOT NULL,
	`reusable` integer DEFAULT 0 NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `qr_codes_id_unique` ON `qr_codes` (`id`);--> statement-breakpoint
CREATE TABLE `qr_intents` (
	`order_id` text PRIMARY KEY NOT NULL,
	`qr_id` text NOT NULL,
	`snapshot` text NOT NULL,
	`created_at` text NOT NULL
);
