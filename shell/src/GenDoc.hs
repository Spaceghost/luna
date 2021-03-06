{-# LANGUAGE OverloadedStrings #-}

import           Luna.Prelude        hiding (String, seq, cons, Constructor)
import qualified Luna.Prelude        as P
import qualified Data.Map            as Map
import           Data.Map            (Map)
import qualified Data.TreeSet        as TreeSet
import           Control.Monad.Raise
import           Control.Monad.State  (runStateT, MonadState)
import           Control.Monad.Except (runExceptT, MonadError, throwError)

import qualified OCI.Pass           as Pass
import           OCI.Pass           (SubPass, Preserves, Inputs, Outputs)
import qualified OCI.IR.Repr.Vis    as Vis
import OCI.IR.Name.Qualified
import Luna.IR
import Luna.IR.Term.Unit (UnitSet)
import Luna.IR.Term.Cls  (Cls)
import qualified Luna.IR.Term.Unit as Term
import qualified Luna.IR.Term.Unit as Unit
import qualified Luna.IR.Term.Cls  as Term
import Luna.Builtin.Data.Module     as Module
import Luna.Builtin.Data.Class
import Luna.Builtin.Data.LunaEff
import qualified Luna.Builtin.Data.Function   as Function

import Luna.Pass.Data.UniqueNameGen
import Luna.Pass.Data.ExprRoots

import qualified Luna.Syntax.Text.Parser.Parser   as Parser
import qualified Luna.Syntax.Text.Source          as Source
import qualified Luna.Syntax.Text.Parser.Parsing  as Parsing
import qualified Luna.Syntax.Text.Parser.Class    as Parsing
import qualified Luna.Syntax.Text.Parser.Marker   as Parser (MarkedExprMap)
import qualified Luna.Syntax.Text.Parser.CodeSpan as CodeSpan
import qualified Luna.Syntax.Text.Layer.Loc       as Loc
import qualified Data.Text.Position               as Pos

import Luna.Test.IR.Runner
import Data.TypeDesc
import System.IO.Unsafe

import qualified Luna.Pass.Transform.Desugaring.RemoveGrouped  as RemoveGrouped
import qualified Luna.Pass.UnitCompilation.ModuleProcessing    as ModuleProcessing
import qualified Luna.Pass.Sourcing.UnitLoader as UL
import           Luna.Syntax.Text.Parser.Errors      (Invalids)

import qualified Luna.Project       as Project
import           System.Directory   (getCurrentDirectory)
import qualified System.Environment as Env

import System.Log (dropLogs)

initPM = do
    runRegs

    Loc.init
    attachLayer 5 (getTypeDesc @Pos.Range)         (getTypeDesc @AnyExpr)
    CodeSpan.init
    attachLayer 5 (getTypeDesc @CodeSpan.CodeSpan) (getTypeDesc @AnyExpr)
    initNameGen
    setAttr (getTypeDesc @Parser.MarkedExprMap)   $ (mempty :: Parser.MarkedExprMap)
    setAttr (getTypeDesc @Parser.ParsedExpr)      $ (error "Data not provided: ParsedExpr")
    setAttr (getTypeDesc @Parser.ReparsingStatus) $ (mempty :: Parser.ReparsingStatus)
    setAttr (getTypeDesc @WorldExpr)     (undefined :: WorldExpr)
    setAttr (getTypeDesc @Source.Source) (undefined :: Source.Source)
    setAttr (getTypeDesc @Invalids)               $ (mempty :: Invalids)
    setAttr (getTypeDesc @UnitSet)                  (undefined :: UnitSet)
    setAttr (getTypeDesc @UL.UnitsToLoad)           (mempty    :: UL.UnitsToLoad)
    setAttr (getTypeDesc @UL.SourcesManager)        (undefined :: UL.SourcesManager)
    Pass.eval' initWorld

main = do
    [path] <- Env.getArgs
    code   <- readFile path
    runPM True $ do
        initPM
        u <- Pass.eval' @UL.UnitLoader $ do
            u   <- UL.parseUnit code
            cls <- u @^. Unit.cls
            UL.partitionASGCls (unsafeGeneralize cls :: Expr ClsASG)
            return u
        imps <- ModuleProcessing.processModule def "Module" u
        print $ itoListOf (importedFunctions .> itraversed <.  Function.documentation) imps
        print $ itoListOf (importedClasses   .> itraversed <.  Function.documentation) imps
        print $ itoListOf (importedClasses   .> itraversed <.> Function.documentedItem . methods .> itraversed <. Function.documentation) imps


