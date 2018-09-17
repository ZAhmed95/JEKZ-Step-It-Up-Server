var express = require('express');
var pg = require('pg');
var bodyParser = require('body-parser');
var path = require('path');
var PORT = process.env.PORT || 5000;
var session = require('express-session');
var sessionStore = require('connect-pg-simple')(session);
var bcrypt = require('bcrypt');
var saltRounds = 10;
var passport = require('passport');
var LocalStrategy = require('passport-local').Strategy;
var app = express();

app.use(express.static(path.join(__dirname, 'public')))
app.use(bodyParser())
app.set('views', path.join(__dirname, 'views'))
app.set('view engine', 'ejs')

//connection string for connecting to postgres database
var connectionString = process.env.DATABASE_URL;

app.use(session({
  store: new sessionStore({
    conString: connectionString
  }),
  secret: 'jekz',
  resave: false,
  saveUninitialized: true,
  cookie: {
    maxAge: 7*24*60*60*1000 //7 days
  }
}));
app.use(passport.initialize());
app.use(passport.session());

//authentication strategy
passport.use(new LocalStrategy(
  function(username, password, done) {
    //connect to database
    pg.connect(connectionString, function(err,client,pgdone){
      if(err){
        console.log("error connecting to database");
        return done(err);
      }
      username = username.toLowerCase();
      //find matching user and password
      client.query(`select * from users where username = '${username}';`, function(err,result){
        pgdone();
        pg.end();
        if(err){
          console.log("error querying database");
          return done(err);
        }
        if (result.rows.length){ //user found
          //get user's hashed Password
          hash = result.rows[0].password
          //verify input Password
          if(bcrypt.compareSync(password, hash)) {
            //passwords match, log user in
            row = result.rows[0];
            user = {
              "userid" : row.userid,
              "username" : row.username
            };
            return done(null, user);
          }
          else{
            //passwords don't match
            return done(null, false);
          }
        }
        //user not found
        return done(null, false);
      }); //end client.query
    }); //end pg.connect
  } //end strategy function
)); //end passport.use(new LocalStrategy())

passport.serializeUser(function(user, done) {
  done(null, user);
});

passport.deserializeUser(function(user, done) {
  done(null, user);
});

//start listening
app.listen(PORT, () => console.log(`Listening on ${ PORT }`))

app.get('/', function(req,res){
  if(req.user){
    res.redirect(`/${req.user.username}`);
  }
  else{
    res.render('pages/index');
  }
});

//FOR TESTING PURPOSES, NOTHING IN THIS BLOCK IS PRODUCTION CODE
app.post('/loggedin', function(req, res){
  return res.json(req.user || {"user" : "None"});

  if (req.user){
    user = {
      "userid" : req.user.userid,
      "username" : req.user.username
    };
    return res.json(user);
  }
  return res.json({"user" : "None"});
});

app.post('/test/session', function(req,res){
  return res.json(req.session);
});
//END TESTING BLOCK

app.get('/login', (req, res) => res.render('pages/login'))

app.post('/login', passport.authenticate('local', {
  successRedirect: '/',
  failureRedirect: '/login'}
));

app.get('/logout', function(req,res){
  req.logout();
  res.redirect('/');
});

app.get('/signup', (req, res) => res.render('pages/signup'))

//username checker function for new user
var checkUsername = function(username){
  return /^[0-9a-z]+$/.test(username);
};

app.post('/signup', function(req,res){
  pg.connect(connectionString, function(err,client,done){
    if(err){
      return console.log("error connecting to database");
    }
    var username = req.body.username.toLowerCase();
    //check username to see if it's valid
    if (!checkUsername(username)){
      return res.json({"error":"invalid username. Username can only contain letters and digits."});
    }
    var password = req.body.password;
    //hash password and attempt to store user in DB
    bcrypt.hash(password, saltRounds, function(err, hash){
      client.query(`SELECT add_user('${username}','${hash}');`, function(err,result){
        if(err){
          res.send(err);
          return console.log("error inserting into database");
        }
        res.redirect('/');
        done();
        pg.end();
      }); //end client.query
    }); //end bcrypt.hash
  }); //end pg.connect
}); //end app.post

app.post('/api/db/update', function(req, res){
  //connect to db
  pg.connect(connectionString, function(err, client, done){
    if (err){
      return res.json(err);
    }
    action = req.body.action || req.body.data_type;
    if (req.user){
      userid = req.user.userid;
    }
    else {
      userid = req.body.userid;
    }
    results = [];
    procedure = '';
    queryString = '';
    //based on update_type, choose correct query:
    switch(action){
      case 'sessions':
        start_time = `'${req.body.start_time}'`;
        end_time = `'${req.body.end_time}'`;
        steps = parseInt(req.body.steps);
        procedure = `add_session(${userid},${start_time},${end_time},${steps})`;
        break;

      case 'purchase':
        itemid = parseInt(req.body.itemid);
        change = parseInt(req.body.amount);
        procedure = `purchase_item(${userid},${itemid},${change})`;
        break;

      //DEPRECATED: to equip items, use action : "equip_items"
      case 'user_data':
        hat = parseInt(req.body.hat);
        shirt = parseInt(req.body.shirt);
        pants = parseInt(req.body.pants);
        shoes = parseInt(req.body.shoes);
        procedure = `equip_items(${userid},${hat},${shirt},${pants},${shoes})`;
        break;

      case 'equip_items':
        hat = parseInt(req.body.hat);
        shirt = parseInt(req.body.shirt);
        pants = parseInt(req.body.pants);
        shoes = parseInt(req.body.shoes);
        procedure = `equip_items(${userid},${hat},${shirt},${pants},${shoes})`;
        break;

      case 'update_user_info':
        weight = parseFloat(req.body.weight);
        height = parseFloat(req.body.height);
        gender = `'${req.body.gender}'`;
        procedure = `update_user_info(${userid},${weight},${height},${gender})`;
        break;

      case 'set_daily_goal':
        daily_goal = parseInt(req.body.daily_goal);
        procedure = `set_daily_goal(${userid},${daily_goal})`;
        break;

      case 'request_friend':
        friendid = parseInt(req.body.friendid);
        procedure = `request_friend(${userid},${friendid})`;
        break;

      case 'accept_friend':
        friendid = parseInt(req.body.friendid);
        procedure = `accept_friend(${userid},${friendid})`;
        break;

      case 'deny_friend':
        friendid = parseInt(req.body.friendid);
        procedure = `deny_friend(${userid},${friendid})`;
        break;

      case 'remove_friend':
        friendid = parseInt(req.body.friendid);
        procedure = `remove_friend(${userid},${friendid})`;
        break;

      //TODO: finish switch statement
	    default:
        done();
        pg.end();
		    return res.send('[{"Error" : "Invalid action string."}]');
    }

    //HOTFIX for server crashing, remove later
    if (procedure === ''){
      return;
    }
    queryString = `SELECT * FROM ${procedure};`;
    client.query(queryString, function(error, result){
      if (error){
        done();
        pg.end();
        return res.json(error);
      }
      done();
      pg.end();
      data = {
        'rows' : result.rows,
        'return_data' : action
      }
      return res.json(data);
    });
  }); //end pg.connect
}); //end app.post /api/db/update

app.post('/api/db/retrieve', function(req, res){
  pg.connect(connectionString, function(err, client, done){
    if (err){
      res.send("error connecting to database.");
    }
    action = req.body.action || req.body.data_type;
    if (req.user){
      userid = req.user.userid;
    }
    else{
      userid = parseInt(req.body.userid);
    }

    results = [];
    procedure = '';
    queryString = '';
    switch(action){
      case 'get_items':
        procedure = `get_items(${userid})`;
        break;

      case 'user_data':
        procedure = `get_user_data(${userid})`;
        break;

      case 'steps_by_date':
        date = `'${req.body.date}'`;
        procedure = `get_steps_by_date(${userid},${date})`;
        break;

      case 'steps_by_week':
        date = `'${req.body.date}'`;
        procedure = `get_weekly_data(${userid},${date})`;
        break;

      case 'friends':
        procedure = `get_friends(${userid})`;
        break;

      case 'pending_friends':
        procedure = `get_pending(${userid})`;
        break;

      case 'search_user':
        username = `'${req.body.username.toLowerCase()}'`;
        procedure = `search_user(${username})`;
        break;

      default:
        done();
        pg.end();
        return res.send('[{"Error" : "Invalid action string."}]');

    }
    //HOTFIX for server crashing, remove later
    if (procedure === ''){
      return;
    }
    queryString = `SELECT * FROM ${procedure};`;
    client.query(queryString, function(error, result){
      if (error){
        done();
        pg.end();
        return res.json(error);
      }
      done();
      pg.end();
      data = {
        'rows' : result.rows,
        'return_data' : action
      }
      return res.json(data);
    });
  }); //end pg.connect
}); //end app.get

//EXPERIMENTAL SECTION:
app.get('/:username/territory', function(req,res){
  if (req.user){
    if (req.user.username === req.params.username){
      //this is the logged in user's own home page
      pg.connect(connectionString, function(err, client, done){
          if (err){
            done(err);
            console.log("Error retrieving data");
            res.redirect('/');
          }
          client.query(`SELECT * FROM territories WHERE userid = ${req.user.userid};`, function(err,result){
            if (err){
              done(err);
              console.log("Error retrieving data");
              res.redirect('/');
            }

            res.render('pages/test', {
              user: req.user,
              data: result.rows
            });
          })//end client.query
      }); //end pg.connect
    }
    else{
      //this is another user's page
      res.redirect('/');
    }
  }
  else{
    //this is another user's page
    res.redirect('/');
  }
}); //end app.get

app.post('/api/updateTerritory', function(req, res){
    userid = req.body.userid;
    lat = req.body.lat;
    lng = req.body.lng;
    pg.connect(connectionString, function(err, client, done){
      client.query(`SELECT * FROM territories WHERE userid=${userid} AND lat=${lat} AND lng=${lng};`, function(err, result){
        if (err){
          console.log("error querying database");
          done();
          return res.send({status : 'error'});
        }
        if (result.rows.length){
          console.log("User already owns this territory");
          done();
          return res.send({status : 'already owned'});
        }
        client.query(`INSERT INTO territories (userid, lat, lng, level) VALUES (${userid}, ${lat}, ${lng}, 0);`, function(err, result){
          if (err){
            console.log("Error inserting into database");
            done();
            return res.send({status : 'error'});
          }
          console.log("Successfully inserted into database");
          done();
          return res.send({status : 'success'});
        }); //end insert into DB
      }); //end select from DB
    }); //end pg.connect
}); //end app.post
//END EXPERIMENTAL SECTION

app.get('/:username', function(req, res){
  if (req.user){
    if (req.user.username === req.params.username){
      //this is the logged in user's own home page
      res.render('pages/home', {
        user: req.user.username
      });
    }
    else{
      //this is another user's page
      res.redirect('/');
    }
  }
  else{
    //this is another user's page
    res.redirect('/');
  }
}); //end app.get

app.get('*', (req, res) => res.render('pages/page404'))
