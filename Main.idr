module Main

%include javascript "pong_helper.js"

syntax inlineJS [code] = mkForeign (FFun code [] FUnit)

record Paddle : Type where
  MkP : (pCenter : Float) -> (pHeight : Float) -> Paddle

record Ball : Type where
  MkB : (bCenter : (Float, Float)) -> (bRad : Float) -> (velocity : (Float, Float)) -> Ball

record PongState : Type where
  MkSt : (ball : Ball) -> (fieldSize : (Float, Float)) -> (left : Paddle) -> (right : Paddle)
       -> PongState

record PongParams : Type where
  MkPms : (aiSpeed : Float) -> (twistFactor : Float) -> 
          (paddleHeight : Float) -> (paddleWidth : Float) ->
          (accelFactor : Float) -> (vx0Factor : Float) -> (vy0Factor : Float) ->
          PongParams

defaultParams : PongParams
defaultParams = MkPms 2 1 50 4 1.05 3 1.2

data Phase = Playing | ShowScore | Waiting | Menu
data Game : Phase -> Type where
  Play : PongParams -> PongState -> (Int, Int) -> Game Playing
  Report : PongParams -> (Int, Int) -> (duration : Int) -> Game ShowScore
  Wait : PongParams -> PongState -> (Int, Int) -> (duration : Int) -> Game Waiting
  --Choose : Game Menu

-- Functions for manipulating the game state
record InputState : Type where
  MkI : (mouseY : Float) -> InputState

boundVelocity : Float -> (Float, Float) -> Float -> Float
boundVelocity x (lower, upper) = case (x <= upper, x >= lower) of
  (True, True) => id
  (True, False) => abs
  (False, True) => negate . abs
  (False, False) => believe_me "impossible"

collides : PongParams -> Ball -> Paddle -> Paddle -> Float -> Ball
collides pms b (MkP pyl phl) (MkP pyr phr) pxr' = record { bCenter = newP, velocity = newV } b where
  x : Float
  x = fst (bCenter b)
  y : Float
  y = snd (bCenter b)
  pw : Float
  pw = paddleWidth pms
  pxl : Float
  pxl = 0
  pxr : Float
  pxr = pxr' - pw
  left : Bool
  left = y <= pyl + phl/2 && y >= pyl - phl/2 && x <= pxl + pw && x >= pxl
  right : Bool
  right = y <= pyr + phr/2 && y >= pyr - phr/2 && x <= pxr + pw && x >= pxr
  newX : Float
  newX = if left then pxl + pw + bRad b
                 else (if right then pxr - bRad b else x)
  newVX : Float
  newVX = if left then abs (fst (velocity b))
                  else (if right then - abs (fst (velocity b)) else fst (velocity b))
  factor : Float
  factor = if left || right then accelFactor pms else 1
  newP = (newX, y)
  vy : Float
  vy = snd (velocity b)
  dvy : Float
  dvy = if left then twistFactor pms * (y - pyl) / phl
                else (if right then twistFactor pms * (y - pyr) / phr else 0)
  newV = (newVX * factor, vy * factor + dvy)

data Outcome = HumanWins | AIWins

aiTrack : Paddle -> Float -> Ball -> Paddle
aiTrack rightPaddle w (MkB (x, y) r (vx, vy)) = 
  if x > 3*w/4 
    then record {pCenter = pCenter rightPaddle + pvy} rightPaddle
    else record {pCenter = pCenter rightPaddle + pvy*abs pvy/4} rightPaddle
 where boundMagnitude : Float -> Float -> Float
       boundMagnitude mag val = min mag (max (-mag) val)
       pvy = boundMagnitude 2 (2 * (y - pCenter rightPaddle) / pHeight rightPaddle)

step : PongParams -> Float -> InputState -> PongState -> Either Outcome PongState
step pms deltaT (MkI mouseY) (MkSt (MkB (x, y) r (vx, vy)) (w, h) leftPaddle rightPaddle) =
   Right (MkSt !newBall (w, h) newLeft !newRight)
     where newVY : Float
           newVY = boundVelocity y (0, h) vy
           newVX : Float
           newVX = boundVelocity x (0, w) vx
           newLeft = record { pCenter = mouseY } leftPaddle
           movedBall : Ball
           movedBall = (MkB (x + vx*deltaT, y + vy*deltaT) r (newVX, newVY))
           newBall = if x < 0 || x > w 
                        then (if x < 0 then Left AIWins else Left HumanWins)
                        else Right (collides pms movedBall leftPaddle rightPaddle w)
           newRight = Right (aiTrack rightPaddle w !newBall)

-- functions for manipulating the canvas
setFillStyle : String -> IO ()
setFillStyle color = mkForeign (FFun "setFillStyle(%0)" [FString] FUnit) color
clear : String -> IO ()
clear color = do
  setFillStyle color
  inlineJS "context.fillRect(0, 0, canvas.width, canvas.height)"

circle : (Float, Float) -> Float -> IO ()
circle (x, y) rad = do
  inlineJS "context.beginPath()"
  mkForeign (FFun "context.arc(%0, %1, %2, 0, 2*Math.PI, false)" [FFloat, FFloat, FFloat] FUnit) x y rad
  inlineJS "context.fill()"

rect : (Float, Float) -> (Float, Float) -> IO ()
rect (x, y) (w, h) = do
  mkForeign (FFun "context.fillRect(%0, %1, %2, %3)" [FFloat, FFloat, FFloat, FFloat] FUnit) x y w h

draw : PongState -> IO ()
draw (MkSt (MkB p r v) (w,h) (MkP ly lh) (MkP ry rh)) = do
  clear "#000000"
  setFillStyle "#FFFFFF"
  height <- mkForeign (FFun "canvas.height" [] FInt)
  rect (0, ly - lh/2) (4, lh)
  rect (w-4, ry - rh/2) (4, rh)
  circle p 5

newGame : PongParams -> IO PongState
newGame pms = do
  width <- mkForeign (FFun "canvas.width" [] FFloat)
  height <- mkForeign (FFun "canvas.height" [] FFloat)
  angle <- mkForeign (FFun "Math.random() * 2 * Math.PI" [] FFloat)
  vx <- mkForeign (FFun "Math.sin(%0)" [FFloat] FFloat) angle
  vy <- mkForeign (FFun "Math.cos(%0)" [FFloat] FFloat) angle
  let ball = MkB (width/2, height/2) 4 (vx*vx0Factor pms, vy*vy0Factor pms)
  let paddle = MkP (height/2) (paddleHeight pms)
  return (MkSt ball (width, height) paddle paddle)

drawReport : (Int, Int) -> IO ()
drawReport (h, ai) = do
    clear "#000000"
    setFillStyle "#FFFFFF"
    fillText (show h) (50, 100)
    fillText (show ai) (260, 100)
  where fillText : String -> (Int, Int) -> IO ()
        fillText s (x, y) = mkForeign (FFun "context.fillText(%0, %1, %2)" [FString, FInt, FInt] FUnit)
                                        s x y

setTimeout : (() -> IO a) -> Float -> IO ()
setTimeout {a} f millis =
    mkForeign (FFun "setTimeout(%0, %1)" [FFunction FUnit (FAny (IO a)), FFloat] FUnit) f millis

partial
play : PongParams -> PongState -> (Outcome -> IO ()) -> IO ()
play pms p f = do
  clear "#000000"
  draw p
  mouse <- mkForeign (FFun "mouseY" [] FFloat)
  case (step pms 1 (MkI mouse) p) of
    Right next => setTimeout (\() => play pms next f) (1000/60)
    Left winner => f winner

partial
run : Game phase -> IO ()
run (Play pms st (h, ai)) = play pms st report where
  report HumanWins = run (Report pms (h+1, ai) 2)
  report AIWins = run (Report pms (h, ai+1) 2)
run (Report pms score duration) = do
  drawReport score
  st <- newGame pms
  setTimeout (\() => run (Wait pms st score 2)) (cast duration * 1000)
run (Wait pms st score duration) = do
  draw st
  setTimeout (\() => run (Play pms st score)) (cast duration * 1000)

partial
main : IO ()
main = do
  width <- mkForeign (FFun "canvas.width" [] FInt)
  height <- mkForeign (FFun "canvas.height" [] FInt)
  run (Report defaultParams (0, 0) 1)
