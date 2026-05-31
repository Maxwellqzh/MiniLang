module MiniLang.Repl where

import Control.Exception (IOException, catch)
import Data.Char (isSpace)
import qualified Data.Map as Map
import MiniLang.Backend.Eval (runProgramWithEnv)
import MiniLang.Backend.Value (Env)
import MiniLang.Parsing.Parser (parseProgram)
import MiniLang.Typecheck.Checker (typecheckProgram)
import MiniLang.Typecheck.Type (TypeEnv, emptyTypeEnv)
import System.IO (hFlush, stdout)
import System.IO.Error (isEOFError)

data ReplState = ReplState
  { replRuntimeEnv :: Env
  , replTypeEnv :: TypeEnv
  }

data ReplInput
  = ReplEOF
  | ReplCommand String
  | ReplSource String

repl :: IO ()
repl = do
  putStrLn "MiniLang REPL. Type :help for help."
  loop (ReplState Map.empty emptyTypeEnv)

loop :: ReplState -> IO ()
loop state = do
  input <- readReplInput
  case input of
    ReplEOF ->
      putStrLn ""
    ReplCommand command ->
      handleCommand state command
    ReplSource source ->
      runSource state source

handleCommand :: ReplState -> String -> IO ()
handleCommand state command =
  case command of
    ":q" -> pure ()
    ":quit" -> pure ()
    ":help" -> do
      printHelp
      loop state
    ":env" -> do
      print (replRuntimeEnv state)
      loop state
    ":reset" -> do
      putStrLn "Environment cleared."
      loop (ReplState Map.empty emptyTypeEnv)
    _ -> do
      putStrLn ("Unknown REPL command: " ++ command)
      loop state

runSource :: ReplState -> String -> IO ()
runSource state source =
  case parseProgram source of
    Left err -> do
      putStrLn ("Parse error: " ++ show err)
      loop state
    Right program ->
      case typecheckProgram (replTypeEnv state) program of
        Left err -> do
          putStrLn ("Type error: " ++ show err)
          loop state
        Right nextTypeEnv ->
          case runProgramWithEnv (replRuntimeEnv state) program of
            Left err -> do
              putStrLn ("Runtime error: " ++ show err)
              loop state
            Right (output, nextRuntimeEnv) -> do
              mapM_ putStrLn output
              loop (ReplState nextRuntimeEnv nextTypeEnv)

readReplInput :: IO ReplInput
readReplInput = collect True []
  where
    collect isFirst linesSoFar = do
      putStr (if isFirst then "minilang> " else "...> ")
      hFlush stdout
      maybeLine <- readLineMaybe
      case maybeLine of
        Nothing ->
          if null linesSoFar
            then pure ReplEOF
            else pure (ReplSource (unlines (reverse linesSoFar)))
        Just line ->
          let command = strip line
           in case () of
                _
                  | null linesSoFar && isCommand command ->
                      pure (ReplCommand command)
                  | all isSpace line ->
                      if null linesSoFar
                        then collect True []
                        else pure (ReplSource (unlines (reverse linesSoFar)))
                  | otherwise ->
                      collect False (line : linesSoFar)

readLineMaybe :: IO (Maybe String)
readLineMaybe =
  (Just <$> getLine) `catch` handleEOF
  where
    handleEOF :: IOException -> IO (Maybe String)
    handleEOF err
      | isEOFError err = pure Nothing
      | otherwise = ioError err

isCommand :: String -> Bool
isCommand text =
  case text of
    ':' : _ -> True
    _ -> False

strip :: String -> String
strip = dropWhileEnd isSpace . dropWhile isSpace

dropWhileEnd :: (a -> Bool) -> [a] -> [a]
dropWhileEnd predicate = reverse . dropWhile predicate . reverse

printHelp :: IO ()
printHelp =
  mapM_
    putStrLn
    [ "Commands:"
    , "  :help   Show this help"
    , "  :env    Show the current environment"
    , "  :reset  Clear the current environment"
    , "  :q      Exit the REPL"
    , "  :quit   Exit the REPL"
    , ""
    , "Enter one or more MiniLang statements, then submit with a blank line."
    , "Example:"
    , "  let x = 1;"
    , "  print x;"
    ]
