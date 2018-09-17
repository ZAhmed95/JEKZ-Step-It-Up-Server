/*
There are a total of 9 tables in the DB. Run the below SQL statements to create each table.
The description of each table is as follows:

1. session
	This table stores the data required to maintain persistent user login sessions. It is not
	directly altered by the app code, but rather utilized by express-session.
	
2. users
	This table stores userids, usernames, and password hashes of all registered users.
	It is used for logging in and searching for users.

3. items
	This table stores all items and their prices available in the shop.
	
4. owned_accessories
	This table stores all the items owned by users.
	
5. session_data
	This table stores users' walking sessions, i.e. session start and end time, and # of steps

6. user_data
	This table stores all general data associated with a user, such as personal preferences,
	overall statistics, total currency, etc.
	
7. friends
	This table stores friend relations between users
	
8. pending_friends
	This table stores friend requests from users to other users; if a request is accepted,
	it is deleted from this table and inserted into friends.
	
9. territories (EXPERIMENTAL)
	This table stores users' owned territories.
	NOTE: this feature is WIP, and not fully implemented.
*/

--TABLE CREATION SCRIPTS
--1. session
DROP TABLE IF EXISTS "session" CASCADE;
CREATE TABLE "session" (
  "sid" varchar NOT NULL COLLATE "default",
	"sess" json NOT NULL,
	"expire" timestamp(6) NOT NULL
)
WITH (OIDS=FALSE);
ALTER TABLE "session" ADD CONSTRAINT "session_pkey"
	PRIMARY KEY ("sid") NOT DEFERRABLE INITIALLY IMMEDIATE;
	
--2. users
DROP TABLE IF EXISTS users CASCADE;
CREATE TABLE users (
	userid SERIAL PRIMARY KEY, 
	username VARCHAR(30) UNIQUE NOT NULL, 
	password VARCHAR(60) NOT NULL
);

--3. items
DROP TABLE IF EXISTS items CASCADE;
CREATE TABLE items (
	itemid SERIAL PRIMARY KEY,
	price NUMERIC NOT NULl DEFAULT 0
);
	
--4. owned_accessories
DROP TABLE IF EXISTS owned_accessories CASCADE;
CREATE TABLE owned_accessories (
	userid INTEGER NOT NULL, 
	itemid INTEGER NOT NULL, 
	count INTEGER NOT NULL DEFAULT 0
);
ALTER TABLE owned_accessories ADD CONSTRAINT owned_accessories_userid_fkey
	FOREIGN KEY(userid) REFERENCES users(userid);
ALTER TABLE owned_accessories ADD CONSTRAINT owned_accessories_itemid_fkey
	FOREIGN KEY(itemid) REFERENCES items(itemid);

--5. session_data
DROP TABLE IF EXISTS session_data CASCADE;
CREATE TABLE session_data (
	userid INTEGER REFERENCES users(userid), 
	start_time TIMESTAMP WITH TIME ZONE NOT NULL, 
	end_time TIMESTAMP WITH TIME ZONE NOT NULL, 
	steps INTEGER NOT NULL
);

--6. user_data
DROP TABLE IF EXISTS user_data CASCADE;
CREATE TABLE user_data (
	userid 			INTEGER PRIMARY KEY, 
	weight 			NUMERIC, --pounds
	height			NUMERIC, --inches
	gender			VARCHAR(20) DEFAULT 'male', 
	total_steps 	BIGINT NOT NULL DEFAULT 0, 
	total_duration 	NUMERIC NOT NULL DEFAULT 0, 
	total_sessions 	INTEGER NOT NULL DEFAULT 0, 
	currency 		NUMERIC NOT NULL DEFAULT 0,
	daily_goal		INTEGER,
	hat 			INTEGER NOT NULL DEFAULT 0,
	shirt 			INTEGER NOT NULL DEFAULT 0,
	pants 			INTEGER NOT NULL DEFAULT 0,
	shoes 			INTEGER NOT NULL DEFAULT 0
);

ALTER TABLE user_data ADD CONSTRAINT user_data_userid_fkey
	FOREIGN KEY (userid) REFERENCES users(userid) ON DELETE CASCADE;
ALTER TABLE user_data ADD CONSTRAINT user_data_hat_fkey 
	FOREIGN KEY(hat) REFERENCES items(itemid);
ALTER TABLE user_data ADD CONSTRAINT user_data_shirt_fkey 
	FOREIGN KEY(shirt) REFERENCES items(itemid);
ALTER TABLE user_data ADD CONSTRAINT user_data_pants_fkey 
	FOREIGN KEY(pants) REFERENCES items(itemid);
ALTER TABLE user_data ADD CONSTRAINT user_data_shoes_fkey
	FOREIGN KEY(shoes) REFERENCES items(itemid);

--7. friends
DROP TABLE IF EXISTS friends CASCADE;
CREATE TABLE friends (
	userid INTEGER REFERENCES users(userid) NOT NULL,
	friendid INTEGER REFERENCES users(userid) NOT NULL,
	UNIQUE (userid, friendid),
	CHECK (userid <> friendid)
);

--8. pending_friends
DROP TABLE IF EXISTS pending_friends CASCADE;
CREATE TABLE pending_friends (
	userid INTEGER REFERENCES users(userid) NOT NULL,
	friendid INTEGER REFERENCES users(userid) NOT NULL,
	UNIQUE (userid, friendid),
	CHECK (userid <> friendid)
);

--9. territories (EXPERIMENTAL)
DROP TABLE IF EXISTS territories CASCADE;
CREATE TABLE territories (
	id SERIAL PRIMARY KEY,
	userid INTEGER,
	lat INTEGER NOT NULL,
	lng INTEGER NOT NULL,
	level SMALLINT NOT NULL
);

ALTER TABLE territories ADD CONSTRAINT territories_userid_fkey
	FOREIGN KEY (userid) REFERENCES users(userid);



