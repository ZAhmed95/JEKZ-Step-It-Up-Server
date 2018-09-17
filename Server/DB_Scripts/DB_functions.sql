/*
This file contains all the functions that the app server utilizes to interact with the DB.
The functions are listed below, grouped by which aspect of the app they relate to.
*/
--1. Registering users
DROP FUNCTION IF EXISTS add_user (TEXT, TEXT);
CREATE OR REPLACE FUNCTION add_user (
	username_ TEXT,
	password_ TEXT
)
RETURNS void AS
$$
DECLARE
	userid_ INTEGER;
BEGIN
	INSERT INTO users (username, password)
	VALUES (username_, password_)
	RETURNING userid INTO userid_;
	
	INSERT INTO user_data (userid)
	VALUES (userid_);
END;
$$ LANGUAGE plpgsql;

--2. Searching for users
DROP FUNCTION IF EXISTS search_user (TEXT);
CREATE OR REPLACE FUNCTION search_user (
	user_name TEXT
)
RETURNS TABLE (
	userid INTEGER,
	username TEXT
) AS
$$
#variable_conflict use_column
BEGIN
	RETURN QUERY
	SELECT
		u.userid,
		u.username
	FROM users as u
	WHERE u.username LIKE CONCAT('%', search_user.user_name, '%');
	
END;
$$ LANGUAGE plpgsql;

--3. Managing user data
--3.1. Retrieve user data
DROP FUNCTION IF EXISTS get_user_data (INTEGER);
CREATE OR REPLACE FUNCTION get_user_data (
	userid INTEGER
)
RETURNS SETOF user_data AS
$$
#variable_conflict use_column
BEGIN
	RETURN QUERY
	SELECT * FROM user_data
	WHERE userid = get_user_data.userid;

END;
$$ LANGUAGE plpgsql;

--3.2. Update user info
DROP FUNCTION IF EXISTS update_user_info (INTEGER, NUMERIC, NUMERIC, VARCHAR);
CREATE OR REPLACE FUNCTION update_user_info (
	IN userid INTEGER,
	IN OUT weight NUMERIC,
	IN OUT height NUMERIC,
	IN OUT gender VARCHAR(20),
	OUT success BOOLEAN,
	OUT message TEXT,
	OUT return_data VARCHAR(20)
)
RETURNS RECORD AS
$$
#variable_conflict use_column
DECLARE
	affected INTEGER;
BEGIN
	--output function type
	SELECT 'update user info' INTO return_data;
	
	--attempt to update user height
	UPDATE user_data SET
		(
			weight, 
			height, 
			gender
		) =
		(
			update_user_info.weight, 
			update_user_info.height, 
			update_user_info.gender
		)
	WHERE update_user_info.userid = userid;
	
	--get affected rows
	GET DIAGNOSTICS affected = ROW_COUNT;
	
	--if affected is null, this user is not in the table
	IF (affected = 0) THEN
		SELECT 'user does not exist.' INTO message;
		SELECT FALSE INTO success;
		RETURN;
	END IF;
	
	SELECT 'user data updated.' INTO message;
	SELECT TRUE INTO success;
	RETURN;
EXCEPTION WHEN OTHERS THEN
	SELECT 'error updating user info.' INTO message;
	SELECT FALSE INTO success;
	RETURN;
END;
$$ LANGUAGE plpgsql;

--3.3. Update user's daily steps goal
DROP FUNCTION IF EXISTS set_daily_goal(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION set_daily_goal (
	userid INTEGER,
	daily_goal INTEGER,
	OUT message TEXT,
	OUT success BOOLEAN
)
RETURNS RECORD AS
$$
#variable_conflict use_column
BEGIN
	SELECT FALSE INTO success;
	
	UPDATE user_data SET daily_goal = set_daily_goal.daily_goal
	WHERE userid = set_daily_goal.userid;
	
	SELECT TRUE INTO success;
	SELECT 'success' INTO message;
	RETURN;
EXCEPTION
WHEN OTHERS THEN
	SELECT SQLERRM INTO message;
	RETURN;
END;
$$ LANGUAGE plpgsql;

--4. Managing session data
--4.1. Get user's walking data for a given day
DROP FUNCTION IF EXISTS get_steps_by_date(INTEGER, DATE);
CREATE OR REPLACE FUNCTION get_steps_by_date (
	IN userid INTEGER,
	IN date DATE,
	OUT total_steps INTEGER,
	OUT total_sessions INTEGER,
	OUT total_hours NUMERIC,
	OUT success BOOLEAN,
	OUT message TEXT,
	OUT return_data VARCHAR(20)
)
RETURNS RECORD AS
$$
#variable_conflict use_column
BEGIN
	--output function type
	SELECT 'steps_by_date' INTO return_data;
	
	WITH S AS (
		SELECT
			steps,
			EXTRACT(epoch FROM (end_time - start_time))/3600.0 AS hours
		FROM session_data AS s
		WHERE s.userid = get_steps_by_date.userid
		AND s.start_time::date = get_steps_by_date.date
	)
	SELECT 
		SUM(steps),
		COUNT(*),
		ROUND(SUM(hours)::numeric, 5)
	INTO
		total_steps,
		total_sessions,
		total_hours
	FROM S;
	
	--set output values to 0 if no rows found
	IF (total_sessions = 0) THEN
		SELECT 0, 0 INTO total_steps, total_hours;
	END IF;
	
	SELECT TRUE INTO success;
	SELECT 'total steps walked.' INTO message;
	RETURN;
EXCEPTION
WHEN OTHERS THEN
	SELECT FALSE INTO success;
	SELECT SQLERRM INTO message;
	RETURN;
END;
$$ LANGUAGE plpgsql;

--4.2. Get user's walking data over a given 7 day period
DROP FUNCTION IF EXISTS get_weekly_data (INTEGER, DATE);
CREATE OR REPLACE FUNCTION get_weekly_data (
	IN userid_ INTEGER,
	IN date_ DATE
)
RETURNS TABLE (
	session_date DATE,
	total_steps INTEGER,
	total_sessions INTEGER,
	total_hours NUMERIC
) AS
$$
BEGIN
	SELECT date_ INTO session_date;
	FOR i IN 0..6
	LOOP
		
		SELECT
			f.total_steps,
			f.total_sessions,
			f.total_hours
		INTO
			total_steps,
			total_sessions,
			total_hours
		FROM
			get_steps_by_date(userid_, session_date) AS f;
			
		RETURN NEXT;
		
		SELECT session_date - 1 INTO session_date;
	END LOOP;
	
	RETURN;
EXCEPTION
WHEN OTHERS THEN
	raise notice '%', SQLERRM;
	RETURN;
END
$$ LANGUAGE plpgsql;

--4.3. Add an entry to session data
DROP FUNCTION IF EXISTS add_session (
	INTEGER, 
	TIMESTAMP WITH TIME ZONE, 
	TIMESTAMP WITH TIME ZONE, 
	INTEGER
);
CREATE OR REPLACE FUNCTION add_session (
	userid INTEGER,
	start_time TIMESTAMP WITH TIME ZONE,
	end_time TIMESTAMP WITH TIME ZONE,
	steps INTEGER,
	OUT message TEXT,
	OUT success BOOLEAN,
	OUT currency_ NUMERIC
)
RETURNS RECORD AS
$$
#variable_conflict use_column
DECLARE
	total_steps_ INTEGER;
	total_sessions_ INTEGER;
	hours NUMERIC;
	total_duration_ NUMERIC;
BEGIN
	SELECT FALSE INTO success;
	
	INSERT INTO session_data (
		userid,
		start_time,
		end_time,
		steps
	)
	VALUES (
		add_session.userid,
		add_session.start_time,
		add_session.end_time,
		add_session.steps
	);
	
	--get user's current stats
	SELECT
		total_steps,
		total_sessions,
		total_duration,
		currency
	INTO 
		total_steps_,
		total_sessions_,
		total_duration_,
		currency_
	FROM user_data
	WHERE userid = add_session.userid;
	
	--update calculate user's new stats
	SELECT total_steps_ + steps INTO total_steps_;
	SELECT total_sessions_ + 1 INTO total_sessions_;
	SELECT EXTRACT(epoch FROM (end_time - start_time))/3600.0 INTO hours;
	SELECT total_duration_ + ROUND(hours::numeric, 5) INTO total_duration_;
	SELECT currency_ + steps INTO currency_;
	
	--update user's stats
	UPDATE user_data SET (
		total_steps,
		total_sessions,
		total_duration,
		currency
	)
	= (
		total_steps_,
		total_sessions_,
		total_duration_,
		currency_
	)
	WHERE userid = add_session.userid;
	
	SELECT TRUE INTO success;
	SELECT 'success' INTO message;
	RETURN;
	
EXCEPTION
WHEN OTHERS THEN
	SELECT SQLERRM INTO message;
	RETURN;
	
END;
$$ LANGUAGE plpgsql;

--5. Managing friends data
--5.1. Get all of a user's current friends
DROP FUNCTION IF EXISTS get_friends(INTEGER);
CREATE FUNCTION get_friends (
	userid INTEGER
)
RETURNS TABLE (
	friendid INTEGER,
	friendname TEXT
) AS
$$
#variable_conflict use_column
BEGIN
	RETURN QUERY
	SELECT
		F.friendid,
		U.username
	FROM friends as F
		JOIN users as U
			ON F.friendid = U.userid
	WHERE F.userid = get_friends.userid;
END;
$$ LANGUAGE plpgsql;

--5.2 Get all pending friend requests to this user
DROP FUNCTION IF EXISTS get_pending(INTEGER);
CREATE FUNCTION get_pending (
	userid INTEGER
)
RETURNS TABLE (
	friendid INTEGER,
	friendname TEXT
) AS
$$
#variable_conflict use_column
BEGIN
	RETURN QUERY
	SELECT
		F.userid,
		U.username
	FROM pending_friends as F
		JOIN users as U
			ON F.userid = U.userid
	WHERE F.friendid = get_pending.userid;
END;
$$ LANGUAGE plpgsql;

--5.3. Send a friend request from this user to another
DROP FUNCTION IF EXISTS request_friend (INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION request_friend (
	userid INTEGER,
	IN OUT friendid INTEGER,
	OUT message TEXT,
	OUT success BOOLEAN
)
RETURNS RECORD AS
$$
#variable_conflict use_column
BEGIN
	SELECT FALSE INTO success;
	
	--if the requested user is already this user's friend, return failure
	IF EXISTS (
		SELECT *
		FROM friends as f
		WHERE f.userid = request_friend.userid
			AND f.friendid = request_friend.friendid
	) THEN
		SELECT 'this user is already a friend.' INTO message;
		RETURN;
	END IF;
	
	--if the requested user has already made a friend request to this user,
	--then instead of sending a request, simply accept theirs
	IF EXISTS (
		SELECT *
		FROM pending_friends as p
		WHERE p.userid = request_friend.friendid
			AND p.friendid = request_friend.userid
	) THEN
		SELECT
			f.message,
			f.success
		INTO
			message,
			success
		FROM accept_friend(request_friend.userid, request_friend.friendid) AS f;
		RETURN;
	END IF;
	
	--otherwise, send a new friend request
	INSERT INTO pending_friends (
		userid,
		friendid
	)
	VALUES (
		request_friend.userid,
		request_friend.friendid
	);
	SELECT 'requested' INTO message;
	SELECT TRUE INTO success;
	RETURN;
EXCEPTION
WHEN foreign_key_violation THEN
	SELECT 'the user does not exist.' INTO message;
	RETURN;
	
WHEN unique_violation THEN
	SELECT 'there is already a pending request to this user.' INTO message;
	RETURN;
	
WHEN OTHERS THEN
	SELECT SQLERRM INTO message;
	RETURN;
END;
$$ LANGUAGE plpgsql;

--5.4. Accept a friend request from another user
DROP FUNCTION IF EXISTS accept_friend (INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION accept_friend (
	userid INTEGER,
	IN OUT friendid INTEGER,
	OUT message TEXT,
	OUT success BOOLEAN
)
RETURNS RECORD AS
$$
#variable_conflict use_column
DECLARE
	deleted INTEGER; --number of rows affected by the delete from pending_friends
BEGIN
	SELECT FALSE INTO success;
		
	--delete row from pending_friends
	DELETE FROM pending_friends AS p
	WHERE p.userid = accept_friend.friendid
		AND p.friendid = accept_friend.userid;
	
	--get number of rows affected by the delete (either 1 or 0)
	GET DIAGNOSTICS deleted = ROW_COUNT;
	
	--if deleted = 0, that means there was no request from this user
	IF (deleted = 0) THEN
		SELECT 'there was no friend request from this user.' INTO message;
		RETURN;
	END IF;
	
	--otherwise,
	--insert two rows into friends
	INSERT INTO friends (
		userid, friendid
	)
	VALUES (
		accept_friend.userid, accept_friend.friendid
	),
	(
		accept_friend.friendid, accept_friend.userid
	);
	
	SELECT TRUE INTO success;
	SELECT 'accepted' INTO message;
	RETURN;
	
EXCEPTION
WHEN OTHERS THEN
	SELECT SQLERRM INTO message;
	RETURN;
END;
$$ LANGUAGE plpgsql;

--5.5. Deny a friend request from another user
DROP FUNCTION IF EXISTS deny_friend(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION deny_friend (
	userid INTEGER,
	IN OUT friendid INTEGER,
	OUT message TEXT,
	OUT success BOOLEAN
)
RETURNS RECORD AS
$$
#variable_conflict use_column
DECLARE
	deleted INTEGER;
BEGIN
	SELECT FALSE INTO success;
	
	DELETE FROM pending_friends AS p
	WHERE p.userid = deny_friend.friendid
		AND p.friendid = deny_friend.userid;
	
	GET DIAGNOSTICS deleted = ROW_COUNT;
	
	IF (deleted = 0) THEN
		SELECT 'No friend request from this user.' INTO message;
		RETURN;
	END IF;
	
	SELECT TRUE INTO success;
	SELECT 'denied friend request.' INTO message;
	RETURN;

EXCEPTION
WHEN OTHERS THEN
	SELECT SQLERRM INTO message;
	RETURN;
END;
$$ LANGUAGE plpgsql;

--5.6. Remove a friend
DROP FUNCTION IF EXISTS remove_friend(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION remove_friend (
	userid INTEGER,
	IN OUT friendid INTEGER,
	OUT message TEXT,
	OUT success BOOLEAN
)
RETURNS RECORD AS
$$
#variable_conflict use_column
DECLARE
	deleted INTEGER;
BEGIN
	SELECT FALSE INTO success;
	
	DELETE FROM friends AS f
	WHERE 
	(f.userid = remove_friend.userid AND f.friendid = remove_friend.friendid)
		OR
	(f.userid = remove_friend.friendid AND f.friendid = remove_friend.userid);
	
	GET DIAGNOSTICS deleted = ROW_COUNT;
	
	IF (deleted = 0) THEN
		SELECT 'this user is not a friend.' INTO message;
		RETURN;
	END IF;
	
	SELECT TRUE INTO success;
	SELECT 'friend removed.' INTO message;
	RETURN;
	
EXCEPTION
WHEN OTHERS THEN
	SELECT SQLERRM INTO message;
	RETURN;
END;
$$ LANGUAGE plpgsql;

--6. Manage user items and accessories
--6.1. Get user's owned items
DROP FUNCTION IF EXISTS get_items (INTEGER);
CREATE OR REPLACE FUNCTION get_items (
	userid INTEGER
)
RETURNS TABLE (
	itemid INTEGER,
	count INTEGER
) AS
$$
#variable_conflict use_column
BEGIN
	RETURN QUERY
	SELECT
		itemid,
		count
	FROM owned_accessories
	WHERE userid = get_items.userid;
END;
$$ LANGUAGE plpgsql;

--6.2. Purchase item from shop
DROP FUNCTION IF EXISTS purchase_item(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION purchase_item(
	IN userid INTEGER, 
	IN OUT itemid INTEGER, 
	IN item_amount INTEGER,
	OUT user_currency NUMERIC,
	OUT success BOOLEAN,
	OUT message TEXT
)
RETURNS RECORD AS
$$
#variable_conflict use_column
DECLARE
	current_count INTEGER; --how many of this item user currently has
	item_price NUMERIC; --this item's shop price
	total_cost NUMERIC; --total cost of purchasing all items
BEGIN
	--get item price
	SELECT i.price INTO item_price
	FROM items AS i
	WHERE i.itemid = purchase_item.itemid;
	
	--get user's money
	SELECT u.currency INTO user_currency
	FROM user_data AS u
	WHERE u.userid = purchase_item.userid;
	
	--if item_price is null, this item doesn't exist
	IF (item_price IS NULL) THEN
		SELECT FALSE INTO success;
		SELECT 'item does not exist.' INTO message;
		RETURN;
	END IF;
	
	--if user_currency is null, this user doesn't exist
	IF (user_currency IS NULL) THEN
		SELECT FALSE INTO success;
		SELECT 'user does not exist.' INTO message;
		RETURN;
	END IF;
	
	--calculate total cost
	SELECT item_price * item_amount INTO total_cost;
	
	--if user doesn't have enough money to buy, return false
	IF (total_cost > user_currency) THEN
		SELECT FALSE INTO success;
		SELECT 'user cannot afford this transaction.' INTO message;
		RETURN;
	END IF;
	
	--get the current_count of this item user has
	SELECT o.count INTO current_count
	FROM owned_accessories AS o
	WHERE o.userid = purchase_item.userid AND o.itemid = purchase_item.itemid;
	
	--deduct money from user
	SELECT user_currency - total_cost INTO user_currency;
	UPDATE user_data SET currency = user_currency
	WHERE user_data.userid = purchase_item.userid;
	
	--If row doesn't exist, insert it
	IF (current_count IS NULL) THEN
		INSERT INTO owned_accessories (userid, itemid, count)
			VALUES (purchase_item.userid, purchase_item.itemid, item_amount);
	--otherwise, update item count
	ELSE
		UPDATE owned_accessories SET count = current_count + item_amount
		WHERE userid = purchase_item.userid AND itemid = purchase_item.itemid;
	END IF;
	
	--return true, indicating successful purchase
	SELECT TRUE INTO success;
	SELECT 'Transaction complete.' INTO message;
	RETURN;
END;
$$ LANGUAGE plpgsql;

--6.3. Update user's equipped items
DROP FUNCTION IF EXISTS equip_items (INTEGER,INTEGER,INTEGER,INTEGER,INTEGER);
CREATE OR REPLACE FUNCTION equip_items (
	IN userid INTEGER,
	IN OUT hat INTEGER,
	IN OUT shirt INTEGER,
	IN OUT pants INTEGER,
	IN OUT shoes INTEGER,
	OUT success BOOLEAN,
	OUT message TEXT
)
RETURNS RECORD AS
$$
#variable_conflict use_column
DECLARE
	affected INTEGER;
BEGIN
	--Attempt to update user data with new items
	UPDATE user_data AS u SET 
		(
			hat, 
			shirt, 
			pants, 
			shoes
		) = 
		(
			equip_items.hat, 
			equip_items.shirt, 
			equip_items.pants, 
			equip_items.shoes
		)
	WHERE userid = equip_items.userid;
	
	--get affected rows
	GET DIAGNOSTICS affected = ROW_COUNT;
	
	--if affected is null, this user is not in the table
	IF (affected = 0) THEN
		SELECT 'user does not exist.' INTO message;
		SELECT FALSE INTO success;
		RETURN;
	END IF;
	
	SELECT 'user data updated.' INTO message;
	SELECT TRUE INTO success;
	RETURN;
EXCEPTION 
WHEN foreign_key_violation THEN
	SELECT 'at least one of the items does not exist.' INTO message;
	SELECT FALSE INTO success;
	RETURN;
	
WHEN OTHERS THEN
	SELECT SQLERRM INTO message;
	SELECT FALSE INTO success;
	RETURN;
END;
$$ LANGUAGE plpgsql;