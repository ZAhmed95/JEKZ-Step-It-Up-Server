/*
This file contains statements to populate every table with dummy values for testing purposes.
NOTE: You must run the statements in DB_tables first, then DB_functions, then this file.
*/
--truncate all tables before populating with test data
TRUNCATE TABLE session;
TRUNCATE TABLE users CASCADE;
TRUNCATE TABLE items CASCADE;


--1. session
--This table does not need to be populated

--3. items
CREATE OR REPLACE FUNCTION populate_items() RETURNS void AS $$
BEGIN
	--itemid 0 means default clothing
	INSERT INTO items (itemid, price) VALUES (0, 0);
	FOR i IN 1..57
	LOOP
		INSERT INTO items (itemid, price) VALUES (i, i*5);
	END LOOP;
	--A few cheap items
	UPDATE items SET price = 10 WHERE itemid IN (7,17,23,25,33,36,54);
END;
$$ LANGUAGE plpgsql;

--execute function
SELECT populate_items();

--drop populate_items function
DROP FUNCTION populate_items();

--2. users

--Three users: user1, user2, and user3, all with password: test
SELECT add_user ('user1','$2a$10$W6EvdgHJLSAtisrXt6puu.nfSaXPo4FYyXBpJq9fnOU/5NDcXCWyq');
SELECT add_user ('user2','$2a$10$/I6ZutYkRkTFzT6ybYSZk.2DT3EkMUNYjx./h.eGjW0DgLgE3.ivy');
SELECT add_user ('user3','$2a$10$ehysO6Fuavmdxo.b.SWapuG40TqiZIcRzu1.hAN0LzNiFKqwlwiCC');

--4. owned_accessories
--give user1, user2, and user3 some items
INSERT INTO owned_accessories (userid, itemid, count) VALUES
	(1,1,1), (1,2,1), (1,3,1),
	(2,4,1), (2,5,1), (2,6,1),
	(3,7,1), (3,8,1), (3,9,1);

--5. session_data
--create function to generate a week's worth of session data for a user
CREATE OR REPLACE FUNCTION populate_sessions(userid INTEGER) RETURNS void AS $$
DECLARE
	today_date TIMESTAMP WITH TIME ZONE = current_timestamp;
	start_time TIMESTAMP WITH TIME ZONE;
	end_time TIMESTAMP WITH TIME ZONE;
BEGIN
	FOR i IN 0..6
	LOOP
		SELECT today_date INTO start_time;
		SELECT start_time + interval '2 hours' INTO end_time;
		PERFORM add_session(userid, start_time, end_time, 2000);
		SELECT today_date - interval '24 hours' INTO today_date;
	END LOOP;
END;
$$ LANGUAGE plpgsql;
--execute function for each user
SELECT populate_sessions(userid) FROM users;

--Drop populate_sessions function
DROP FUNCTION populate_sessions(INTEGER);

--6. user_data
--set various height, weight, gender, and daily_goal values for each user
SELECT update_user_info(1, 150, 68, 'male');
SELECT set_daily_goal(1, 4000);
SELECT update_user_info(2, 160, 70, 'male');
SELECT set_daily_goal(2, 5000);
SELECT update_user_info(3, 120, 64, 'female');
SELECT set_daily_goal(3, 3000);

--7. friends
--make user1 and user2 friends
SELECT request_friend(1,2);
SELECT accept_friend(2,1);

--8. pending_friends
--make a pending friend request from user3 to user1
SELECT request_friend(3,1);

--9. territories (EXPERIMENTAL)
--This is a table for a feature that is not yet fully implemented,
--as such it is not populated with any test data for now