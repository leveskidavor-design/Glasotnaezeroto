CREATE TABLE "boat_devices" (
	"id" text PRIMARY KEY,
	"boat_id" text NOT NULL,
	"token_hash" text NOT NULL UNIQUE,
	"label" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_seen_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "boats" ADD COLUMN "max_devices" integer DEFAULT 1 NOT NULL;--> statement-breakpoint
CREATE INDEX "boat_devices_boat_idx" ON "boat_devices" ("boat_id");--> statement-breakpoint
ALTER TABLE "boat_devices" ADD CONSTRAINT "boat_devices_boat_id_boats_id_fkey" FOREIGN KEY ("boat_id") REFERENCES "boats"("id") ON DELETE CASCADE;