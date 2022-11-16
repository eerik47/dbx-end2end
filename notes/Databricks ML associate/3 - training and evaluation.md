- [Algorithms](#algorithms)
  - [Linear regression](#linear-regression)
  - [Decision tree](#decision-tree)
  - [Random forest](#random-forest)
  - [Gradient Boosting trees](#gradient-boosting-trees)
- [Training](#training)
- [Save model](#save-model)
- [Hyperparameter tuning](#hyperparameter-tuning)
  - [ParamGridBuilder](#paramgridbuilder)
  - [Cross validation](#cross-validation)
  - [HyperOpt](#hyperopt)
- [Model evaluation](#model-evaluation)
  - [Common metrics](#common-metrics)
  - [Linear Regression - get coefficients and intercept](#linear-regression---get-coefficients-and-intercept)
  - [Evaluate regression model](#evaluate-regression-model)
  - [Evaluate classification model](#evaluate-classification-model)
- [AutoML](#automl)


# Algorithms
## Linear regression
y = ax + b

- Predicts continuous values such as price
- Simple, fast to train, can be paralellized with MLLib in Spark
- Easy to interpret - coefficients (weights) of features tell about how model works
- Easy to tune (less worry about overfitting etc.)
- Not accurate for complex problems
- We need to convert categorical values to OHE (dummy variables) - not just indexer, because such numbers have no numerical meanings (if 1=cat, 2=dog, 3=mouse, it does not mean that dog is more than cat but less then mouse)

```python
lr = Lin
```

## Decision tree
- Tree of binary (true/false) decisions such as feature1 below or above median and so on
- Predicts categorical value such as buy/not-buy, cheap/expensive
- For regression problems, the predicted value is the mean of the training values in the leaf node
- First decision -> find feature that after split gives most information gain = best segregates responses (most blue on left, most red on right)
- Then repeat on next level -> find most information gain on split -> after you reach max depth or all responses are same
- We need to stop splitting at some point to avoid overfitting
- Easy to interpret
- Can capture non-linear problems
- Few hyperparameters to tune
- In MLLib we still need to convert all features to vector, but we will not use OHE (just indexer)

```python
dt = DecisionTreeRegressor(labelCol="price")
```

## Random forest
- Create multiple decision trees and average their predictions
- Key is to create trees that are different from each other (uncorrelated)
  - Bootstrap aggregation - each tree is trained on a random sample of the data
  - Feature randomness - each tree is trained on a random subset of features
- Hyperparameters to tune:
  - Number of trees (numTrees in MLLib, n_estimators in sklearn)
  - Max depth (maxDepth in MLLib, max_depth in sklearn)
  - Max bins (maxBins in MLLib, not in sklearn and it is not distributed)
  - Max features (featureSubsetStrategy in MLLib, max_features in sklearn)

```python
rf = RandomForestRegressor(labelCol="price", maxBins=40)
```

## Gradient Boosting trees
 - Create multiple (simple, called "weak learner") decision trees and combine them in sequence where each tree tries to correct errors of previous tree (residuals of previous tree is label for next tree)
 - y = a*tree1(x) + b*tree2(x) + c*tree3(x) + ...
 - We only add new tree to the model as long as gradient is closer to zero (slope is less steep, so we are closer to minimum)
 - Pretty similar to gradient descent used in deep learning
 - Can overfit easily
 - Somewhat between Linear Regression and Deep Neural Networks because it:
   - Can achieve good performance in quite complex problems (closer to DNNs)
   - For complex yet structured data try GBT first, for unstructured problems like vision/pixels, try DNNs first
   - It is still easier to compute than DNNs (cheaper, faster learning), but hard to parallelize
   - Interpretability is no longer as good as LR
   - XGBoost is the most popular implementation of GBT
   - LightGBM by Microsoft - faster especially for larger datasets, but can more easily overfit (it produces more complex trees)

```python
from sparkdl.xgboost import XgboostRegressor
from pyspark.ml import Pipeline

params = {"n_estimators": 100, "learning_rate": 0.1, "max_depth": 4, "random_state": 42, "missing": 0}

xgboost = XgboostRegressor(**params)

pipeline = Pipeline(stages=[string_indexer, vec_assembler, xgboost])
pipeline_model = pipeline.fit(train_df)
```

# Training
First we need to declare model, in this example LiearRegression, where we need to specify features and label.

```python
lr = LinearRegression(featuresCol="features", labelCol="price")
```

Then we can just run fit on it with vectorized DataFrame as input.

```python
lr_model = lr.fit(vec_train_df)
```

More often we will use rather pipeline which is list of transformations applied. Here we appy following set of operations:
1. String index is converting categorical columns to index numbers (1 = cat, 2 = dog)
2. One Hot Encoder that converts this to dummy variables
3. Then we use VectorAssembler that will make our numerical and OHE features as dense vector
4. Final step is ML model itself
5. Once we have this Pipeline object defined, we can fit it on train_df

```python
from pyspark.ml import Pipeline

# Define pipeline
stages = [string_indexer, ohe_encoder, vec_assembler, lr]
pipeline = Pipeline(stages=stages)

# Train
pipeline_model = pipeline.fit(train_df)
```

Most examples here are using MLLib (Spark ML) which is distributed, but for small problems we can use sklearn (will run on driver). Spark 3.0 is adding features to accelerate this. Eg. Pandas can be loaded as Pandas UDF that uses Apache Arrow to efficiently pass data (100x faster than row-at-time Python UDFs). Also supports iterator so it can be efficient in batches. Recently support was added to call Pandas function API directly on PySpark DataFrame.

```python
# Train
import mlflow.sklearn
import pandas as pd
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split

with mlflow.start_run(run_name="sklearn-random-forest") as run:
    # Enable autologging 
    mlflow.sklearn.autolog(log_input_examples=True, log_model_signatures=True, log_models=True)
    # Import the data
    df = pd.read_csv(f"{DA.paths.datasets}/airbnb/sf-listings/airbnb-cleaned-mlflow.csv".replace("dbfs:/", "/dbfs/")).drop(["zipcode"], axis=1)
    X_train, X_test, y_train, y_test = train_test_split(df.drop(["price"], axis=1), df[["price"]].values.ravel(), random_state=42)

    # Create model
    rf = RandomForestRegressor(n_estimators=100, max_depth=10, random_state=42)
    rf.fit(X_train, y_train)

# Load efficiently data from Pandas to Spark DataFrame 
spark_df = spark.createDataFrame(X_test)
from typing import Iterator, Tuple

@pandas_udf("double")
def predict(iterator: Iterator[pd.DataFrame]) -> Iterator[pd.Series]:
    model_path = f"runs:/{run.info.run_id}/model" 
    model = mlflow.sklearn.load_model(model_path) # Load model
    for features in iterator:
        pdf = pd.concat(features, axis=1)
        yield pd.Series(model.predict(pdf))

prediction_df = spark_df.withColumn("prediction", predict(*spark_df.columns))
display(prediction_df)

# Directly calling Pandas API on PySpark DataFrame
def predict(iterator: Iterator[pd.DataFrame]) -> Iterator[pd.DataFrame]:
    model_path = f"runs:/{run.info.run_id}/model" 
    model = mlflow.sklearn.load_model(model_path) # Load model
    for features in iterator:
        yield pd.concat([features, pd.Series(model.predict(features), name="prediction")], axis=1)
    
display(spark_df.mapInPandas(predict, """`host_total_listings_count` DOUBLE,`neighbourhood_cleansed` BIGINT,`latitude` DOUBLE,`longitude` DOUBLE,`property_type` BIGINT,`room_type` BIGINT,`accommodates` DOUBLE,`bathrooms` DOUBLE,`bedrooms` DOUBLE,`beds` DOUBLE,`bed_type` BIGINT,`minimum_nights` DOUBLE,`number_of_reviews` DOUBLE,`review_scores_rating` DOUBLE,`review_scores_accuracy` DOUBLE,`review_scores_cleanliness` DOUBLE,`review_scores_checkin` DOUBLE,`review_scores_communication` DOUBLE,`review_scores_location` DOUBLE,`review_scores_value` DOUBLE, `prediction` DOUBLE""")) 
```

# Save model
Saving and loading model

```python
# Save model to storage
pipeline_model.write().overwrite().save(directory_path)

# Load model from storage
from pyspark.ml import PipelineModel
saved_pipeline_model = PipelineModel.load(directory_path)
```

Most of the time we will use MLflow to track models and save to registry - see MLFlow section.

# Hyperparameter tuning

## ParamGridBuilder
When there are a lot of hyperparameters we can tune, we can use ParamGrid to provide different values to try. Let's try maxDepth 2 or 5 and numTrees 5 or 10.

```python
from pyspark.ml.tuning import ParamGridBuilder

param_grid = (ParamGridBuilder()
              .addGrid(rf.maxDepth, [2, 5])
              .addGrid(rf.numTrees, [5, 10])
              .build())
```

## Cross validation
Tuning hyperparameters by validating against test dataset would leak information from test dataset to training. To avoid this we can use cross validation. We split our training dataset into k folds and then we train k models, each time using different fold as validation dataset and rest as training dataset. Then we average the results. This way we can tune hyperparameters and still have clean testing dataset to evaluate overall model performance.

What we do:
- Create steps in pipeline such as string indexers, vector assempler, model algorith
- Create evaluator
- Create param grid
- Create cross validator
- Create pipeline out of those
- Train the model

```python
from pyspark.ml.tuning import CrossValidator
cv = CrossValidator(estimator=rf, evaluator=evaluator, estimatorParamMaps=param_grid, numFolds=3, seed=42)
```

## HyperOpt
Framework for advanced hyperparameter tuning. Instead of discrete values (like in ParamGrid) we can specify ranges and algorithm is using various techniques to find best values. Also HyperOpt is trying to parallelize the process using SparkTrials - eg. it can run multiple models in parallel on different machines.

```python
def objective_function(params):    
    # set the hyperparameters that we want to tune
    max_depth = params["max_depth"]
    num_trees = params["num_trees"]

    with mlflow.start_run():
        estimator = pipeline.copy({rf.maxDepth: max_depth, rf.numTrees: num_trees})
        model = estimator.fit(train_df)

        preds = model.transform(val_df)
        rmse = regression_evaluator.evaluate(preds)
        mlflow.log_metric("rmse", rmse)

    return rms

from hyperopt import hp

search_space = {
    "max_depth": hp.quniform("max_depth", 2, 5, 1),
    "num_trees": hp.quniform("num_trees", 10, 100, 1)
}

from hyperopt import fmin, tpe, Trials
import numpy as np
import mlflow
import mlflow.spark
mlflow.pyspark.ml.autolog(log_models=False)

num_evals = 4
trials = Trials()
best_hyperparam = fmin(fn=objective_function, 
                       space=search_space,
                       algo=tpe.suggest, 
                       max_evals=num_evals,
                       trials=trials,
                       rstate=np.random.default_rng(42))

# Retrain model on train & validation dataset and evaluate on test dataset
with mlflow.start_run():
    best_max_depth = best_hyperparam["max_depth"]
    best_num_trees = best_hyperparam["num_trees"]
    estimator = pipeline.copy({rf.maxDepth: best_max_depth, rf.numTrees: best_num_trees})
    combined_df = train_df.union(val_df) # Combine train & validation together

    pipeline_model = estimator.fit(combined_df)
    pred_df = pipeline_model.transform(test_df)
    rmse = regression_evaluator.evaluate(pred_df)

    # Log param and metrics for the final model
    mlflow.log_param("maxDepth", best_max_depth)
    mlflow.log_param("numTrees", best_num_trees)
    mlflow.log_metric("rmse", rmse)
    mlflow.spark.log_model(pipeline_model, "model")
```

fmin() with parallelization

```python
spark_trials = SparkTrials(parallelism=2)
```

# Model evaluation

## Common metrics
- rmse (regression) - root mean squared error -> how far are predictions from actual values, lower is better
- r2 (regression) - r-squared -> how much of variance in data is explained by model, higher is better
- areaUnderROC (binary classification)
  - How well model can separate positive and negative examples, higher is better
  - Based on classification threshold plots following two numbers to create ROC curve
    - True Positive Rate (=recall) -> TP / (TP + FN)
    - False Positive Rate -> FP / (FP + TN)
  - Area under curve (AUC) is 0.5 if model is random, 1.0 if perfect
- accuracy (classicifation)
  - How many examples were classified correctly (TP + TN) / (TP + TN + FP + FN)
  - number alone does not tell anything -> for data samples with 99% blue and 1% green, accuracy of 99% is very bad (the same as model that always predicts blue)
- precission (classicifation)
  - What proportion of positive identifications was actually correct? TP / (TP + FP)
  - maximize for costly high-risk treatment (better to have as little false positives as possible = killing healthy person with high-risk unnecessary treatment)
- recall (classicifation)
  - What proportion of actual positives was identified correctly? TP / (TP + FN)
  - maximize for cheeap harmless treatment (better to have false positive = harmless treatment than false negative = death of unidentified patient)


## Linear Regression - get coefficients and intercept
Get resulting coefficients ("slope" of feature, importance) and intercept ("shift" of line).

```python
m = lr_model.coefficients[0]
b = lr_model.intercept

print(f"y = {m:.2f}x + {b:.2f}")
```

## Evaluate regression model
Get predictions for test data and evaluate model

```python
# Apply vector assembler to test data and create features column
vec_test_df = vec_assembler.transform(test_df)

# Get predictions
pred_df = lr_model.transform(vec_test_df)

# Show predictions
pred_df.select("bedrooms", "features", "price", "prediction").show()

# Calcualate root mean squared error and r-squared
from pyspark.ml.evaluation import RegressionEvaluator

regression_evaluator = RegressionEvaluator(predictionCol="prediction", labelCol="price", metricName="rmse")

rmse = regression_evaluator.evaluate(pred_df)
print(f"RMSE is {rmse}")

r2 = regression_evaluator.setMetricName("r2").evaluate(pred_df)
print(f"R2 is {r2}")
```

## Evaluate classification model
We can use BinaryClassificationEvaluator or MulticlassClassificationEvaluator

```python
from pyspark.ml.evaluation import BinaryClassificationEvaluator, MulticlassClassificationEvaluator
evaluator = BinaryClassificationEvaluator(labelCol="priceClass", rawPredictionCol="rawPrediction", metricName="areaUnderROC")
```

# AutoML
Automatically try different algorithms and hyperparameters to find best model. It is using SparkTrials to parallelize the process. Currently it does utilize lightgbm, sklearn and xgboost - so no DNNs.

```python
from databricks import automl

summary = automl.regress(train_df, target_col="price", primary_metric="rmse", timeout_minutes=5, max_trials=10)
```

In UI you will find automl experiment with all runds. Each run has its own generated notebook so you can look at "source code". 