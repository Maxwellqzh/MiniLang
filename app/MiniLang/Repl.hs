module MiniLang.Repl where

import Control.Exception (IOException, catch)
import Data.Char (isSpace)
import qualified Data.Map as Map
import MiniLang.Backend.Eval (runProgramWithEnv)
import MiniLang.Backend.Value (Env)
import MiniLang.Parsing.Parser (parseProgram)
import System.IO (hFlush, stdout)
import System.IO.Error (isEOFError)

data ReplInput
  = ReplEOF
  | ReplCommand String
  | ReplSource String

repl :: IO ()
repl = do
  putStrLn "MiniLang REPL. Type :help for help."
  loop Map.empty

loop :: Env -> IO ()
loop env = do
  input <- readReplInput
  case input of
    ReplEOF ->
      putStrLn ""
    ReplCommand command ->
      handleCommand env command
    ReplSource source ->
      runSource env source

handleCommand :: Env -> String -> IO ()
handleCommand env command =
  case command of
    ":q" -> pure ()
    ":quit" -> pure ()
    ":help" -> do
      printHelp
      loop env
    ":env" -> do
      print env
      loop env
    ":reset" -> do
      putStrLn "Environment cleared."
      loop Map.empty
    _ -> do
      putStrLn ("Unknown REPL command: " ++ command)
      loop env

runSource :: Env -> String -> IO ()
runSource env source =
  case parseProgram source of
    Left err -> do
      putStrLn ("Parse error: " ++ show err)
      loop env
    Right program ->
      case runProgramWithEnv env program of
        Left err -> do
          putStrLn ("Runtime error: " ++ show err)
          loop env
        Right (output, nextEnv) -> do
          mapM_ putStrLn output
          loop nextEnv

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
