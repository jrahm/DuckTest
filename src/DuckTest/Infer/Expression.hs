module DuckTest.Infer.Expression where

import DuckTest.Types
import DuckTest.Internal.Common
import DuckTest.Internal.State
import DuckTest.Monad
import DuckTest.MonadHelper

inferTypeForExpression :: InternalState -> Expr e -> DuckTest e PyType
inferTypeForExpression state expr = do
    ret <- case expr of

      (Var (Ident name pos) _) ->
          maybe' (getVariableType state name)
              (warn (printf "The identifier %s may not be defined" name) pos >> return anyType)
              return

      (Call callexpr args pos) -> do
          exprType <- checkCallExpression state callexpr args pos
          case exprType of
              (Functional args ret) -> return ret
              _ -> return anyType

      (Dot expr (Ident att _) pos) -> do
          exprType <- inferTypeForExpression state expr
          Trace %% "Infer for type | " ++ prettyText expr ++ " :: " ++ prettyType exprType
          case exprType of
              Any -> return Any
              _ -> case getAttribute exprType att of
                      Nothing -> do
                          warn (printf "The expression %s may have no attribute %s\n    %s :: %s" (prettyText expr) att (prettyText expr) (prettyType exprType)) pos
                          return Any
                      Just t -> return t

      _ -> return anyType

    Trace %% prettyText expr ++ " :: " ++ prettyType ret
    return ret


checkCallExpression st lhs args pos = do
    lhsType <- inferTypeForExpression st lhs
    case lhsType of
        Any -> return () -- maybe adda paranoid warning here
        _ -> case callType lhsType of
                Nothing -> warn (printf "The expression %s does not appear to be callable"
                                    (prettyText lhs)) pos
                Just (argTypes, _) ->
                    zipWithM_ (tryMatchExprType st pos) argTypes args
    return lhsType

    where
        tryMatchExprType state pos paramType argExpr = do
            argType <- inferArgType state argExpr
            whenJust (matchType paramType argType)
                (warnTypeError pos)

inferArgType :: InternalState -> Argument e -> DuckTest e PyType
inferArgType st (ArgExpr expr _) = inferTypeForExpression st expr
inferArgType _ _ = return anyType