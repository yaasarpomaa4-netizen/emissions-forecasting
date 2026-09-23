# install and load packages
#install.packages(c("astsa", "readxl", "here", "forecast"))
library(astsa)
library(readxl)
library(here)
library(forecast)

# import data
emission <- read_excel(here("data", "GHG_emissions.xlsx"))

head(emission)
str(emission)
names(emission)

summary(emission$Ghana)
sum(is.na(emission$Ghana))

#create annual time series
ghana_ts <- ts(emission$Ghana,start = 1971,frequency = 1)

range(emission$Year)
nrow(emission)

#plot original series
plot(ghana_ts,type = "l",lwd = 2,xlab = "Year",ylab = "GHG emissions",
     main = "Ghana Energy-Related GHG Emissions")

#log series
log_ghana <- log(ghana_ts)

plot(log_ghana,type = "l",lwd = 2,xlab = "Year",ylab = "Log emissions",
  main = "Log of Ghana GHG Emissions")

#create the differenced series to inspect stationarity and autocorrelation
ghana_diff <- diff(log_ghana)

plot(ghana_diff,type = "l",lwd = 2,xlab = "Year",ylab = "Change in log emissions",
  main = "First Difference of Log Emissions")

acf2(ghana_diff)

#model fitting
model1 <- sarima(log_ghana, 1, 1, 0)
model2 <- sarima(log_ghana, 0, 1, 1)
model3 <- sarima(log_ghana, 1, 1, 1)
model4 <- sarima(log_ghana, 2, 1, 2)

#model comparison
fit_110 <- Arima(log_ghana, order = c(1, 1, 0))
fit_011 <- Arima(log_ghana, order = c(0, 1, 1))
fit_111 <- Arima(log_ghana, order = c(1, 1, 1))
fit_212 <- Arima(log_ghana, order = c(2, 1, 2))

model_comparison <- data.frame(
  Model = c(
    "ARIMA(1,1,0)",
    "ARIMA(0,1,1)",
    "ARIMA(1,1,1)",
    "ARIMA(2,1,2)"
  ),
  AIC = c(
    AIC(fit_110),
    AIC(fit_011),
    AIC(fit_111),
    AIC(fit_212)
  ),
  AICc = c(
    fit_110$aicc,
    fit_011$aicc,
    fit_111$aicc,
    fit_212$aicc
  ),
  BIC = c(
    BIC(fit_110),
    BIC(fit_011),
    BIC(fit_111),
    BIC(fit_212)
  )
)

model_comparison[
  order(model_comparison$AICc),
]

#check selected model
checkresiduals(fit_011)
checkresiduals(fit_111)
checkresiduals(fit_110)
checkresiduals(fit_212)

summary(fit_212)
fit_212$coef
sqrt(diag(fit_212$var.coef))

#forecast with ARIMA (2,1,2)
# Produce five-year forecasts on the log scale
forecast_212 <- forecast(
  fit_212,
  h = 5,
  level = c(80, 95)
)

# Create a copy for plotting on the original scale
forecast_levels <- forecast_212

# Transform both historical observations and forecasts
forecast_levels$x <- exp(forecast_212$x)
forecast_levels$mean <- exp(forecast_212$mean)
forecast_levels$lower <- exp(forecast_212$lower)
forecast_levels$upper <- exp(forecast_212$upper)

plot(
  forecast_levels,
  main = "Five-Year Forecast of Ghana GHG Emissions",
  xlab = "Year",
  ylab = "GHG emissions"
)

forecast_table <- data.frame(
  Year = 2024:2028,
  Forecast = exp(as.numeric(forecast_212$mean)),
  Lower_80 = exp(as.numeric(forecast_212$lower[, "80%"])),
  Upper_80 = exp(as.numeric(forecast_212$upper[, "80%"])),
  Lower_95 = exp(as.numeric(forecast_212$lower[, "95%"])),
  Upper_95 = exp(as.numeric(forecast_212$upper[, "95%"]))
)

round(forecast_table, 3)

#save output
write.csv(
  model_comparison,
  here("results", "model_comparison.csv"),
  row.names = FALSE
)

write.csv(
  forecast_table,
  here("results", "five_year_forecasts.csv"),
  row.names = FALSE
)

#save plot
png(
  here("figures", "ghana_forecast.png"),
  width = 1200,
  height = 800,
  res = 150
)

plot(
  forecast_levels,
  main = "Five-Year Forecast of Ghana GHG Emissions",
  xlab = "Year",
  ylab = "GHG emissions"
)

dev.off()

#Split the Ghana emissions series into training and holdout periods.
# training set from 1971-2018 and hold out period from 2019-2023

library(forecast)
library(here)

ghana_ts

holdout_size <- 5
last_year <- end(ghana_ts)[1]
training_end <- last_year - holdout_size

train <- window(ghana_ts,end = training_end)

test <- window(ghana_ts,start = training_end + 1)

train
test

#Fit a naïve forecast.
#The naïve method predicts that every future value will equal the final training observation.
fc_naive <- naive(train,h = holdout_size)

#Fit a drift forecast.
#The drift method extends the average historical linear change.
fc_drift <- rwf(train,h = holdout_size,drift = TRUE)

#Fit a historical-growth benchmark.
#This calculates the average annual growth rate on the logarithmic scale and projects it forward.
average_log_growth <- mean(diff(log(train)),na.rm = TRUE)

growth_factor <- exp(average_log_growth)

fc_growth <- as.numeric(tail(train, 1)) * growth_factor^(1:holdout_size)

fc_growth

#Fit ARIMA(0,1,1), ARIMA(1,1,1), and ARIMA(2,1,2).
#Fit the models directly to the original emissions series using lambda = 0. This tells R to apply a log transformation internally and return forecasts on the original scale.
fit_011_train <- Arima(train,order = c(0, 1, 1),lambda = 0)

fit_111_train <- Arima(train,order = c(1, 1, 1),lambda = 0)

fit_212_train <- Arima(train,order = c(2, 1, 2),lambda = 0)

#Generate five-year forecasts:
fc_011 <- forecast(fit_011_train,h = holdout_size,biasadj = TRUE)

fc_111 <- forecast(fit_111_train,h = holdout_size,biasadj = TRUE)

fc_212 <- forecast(fit_212_train,h = holdout_size,biasadj = TRUE)

#Evaluate every model using the same holdout observations.
actual <- as.numeric(test)

pred_naive <- as.numeric(fc_naive$mean)
pred_drift <- as.numeric(fc_drift$mean)
pred_growth <- as.numeric(fc_growth)
pred_011 <- as.numeric(fc_011$mean)
pred_111 <- as.numeric(fc_111$mean)
pred_212 <- as.numeric(fc_212$mean)

data.frame(
  Year = time(test),
  Actual = actual,
  Naive = pred_naive,
  Drift = pred_drift,
  Historical_Growth = pred_growth,
  ARIMA_011 = pred_011,
  ARIMA_111 = pred_111,
  ARIMA_212 = pred_212
)

#Compare MAE, RMSE, bias, and MASE where practical.
#MAE: average absolute forecast error
#RMSE: penalizes larger errors more heavily
#Bias: positive means overforecasting; negative means underforecasting
#MASE: error relative to an in-sample naïve benchmark
calculate_metrics <- function(actual, predicted, training_data) {
  errors <- predicted - actual
  mae <- mean(abs(errors), na.rm = TRUE)
  rmse <- sqrt(
    mean(errors^2, na.rm = TRUE)
  )
  bias <- mean(errors, na.rm = TRUE)
  naive_training_mae <- mean(
    abs(diff(as.numeric(training_data))),
    na.rm = TRUE
  )
  mase <- mae / naive_training_mae
  data.frame(
    MAE = mae,
    RMSE = rmse,
    Bias = bias,
    MASE = mase
  )
}

#Ensure forecasts and actual values are compared on the original emissions scale.
comparison_table <- rbind(
  data.frame(
    Model = "Naive",
    calculate_metrics(actual, pred_naive, train)
  ),
  
  data.frame(
    Model = "Drift",
    calculate_metrics(actual, pred_drift, train)
  ),
  
  data.frame(
    Model = "Historical Growth",
    calculate_metrics(actual, pred_growth, train)
  ),
  
  data.frame(
    Model = "ARIMA(0,1,1)",
    calculate_metrics(actual, pred_011, train)
  ),
  
  data.frame(
    Model = "ARIMA(1,1,1)",
    calculate_metrics(actual, pred_111, train)
  ),
  
  data.frame(
    Model = "ARIMA(2,1,2)",
    calculate_metrics(actual, pred_212, train)
  )
)

comparison_table <- comparison_table[
  order(comparison_table$RMSE),
]

row.names(comparison_table) <- NULL

comparison_table

forecast_plot_data <- data.frame(
  Year = as.numeric(time(test)),
  Actual = actual,
  Naive = pred_naive,
  Drift = pred_drift,
  Historical_Growth = pred_growth,
  ARIMA_011 = pred_011,
  ARIMA_111 = pred_111,
  ARIMA_212 = pred_212
)

matplot(
  forecast_plot_data$Year,
  forecast_plot_data[, -1],
  type = "o",
  lty = 1,
  pch = 1:7,
  col = 1:7,
  xlab = "Year",
  ylab = "GHG emissions",
  main = "Holdout Forecast Comparison"
)

legend(
  "topleft",
  legend = names(forecast_plot_data)[-1],
  col = 1:7,
  lty = 1,
  pch = 1:7,
  cex = 0.7
)

#save results
write.csv(
  comparison_table,
  here("results", "holdout_model_comparison.csv"),
  row.names = FALSE
)

write.csv(
  forecast_plot_data,
  here("results", "holdout_forecasts.csv"),
  row.names = FALSE
)

#Does historical growth continue to outperform the other methods when forecasts are evaluated from several different starting years?

#Define an ARIMA forecasting function
#This function fits an ARIMA model using a log transformation and returns forecasts on the original emissions scale.
get_arima_forecast <- function(training_data, model_order, horizon) {
  
  tryCatch({
    
    fitted_model <- Arima(
      training_data,
      order = model_order,
      lambda = 0
    )
    
    model_forecast <- forecast(
      fitted_model,
      h = horizon,
      biasadj = TRUE
    )
    
    as.numeric(model_forecast$mean)
    
  }, error = function(e) {
    
    # Return missing values if a model fails at one origin
    rep(NA_real_, horizon)
    
  })
}

#Set the validation period
#We will start with a training sample ending in 2000 and produce five-year forecasts from every possible origin through 2018.
forecast_horizon <- 5

first_origin <- 2000
last_year <- end(ghana_ts)[1]
last_origin <- last_year - forecast_horizon

origins <- first_origin:last_origin

origins

#Run the rolling-origin validation
validation_list <- list()
result_number <- 1

for (origin in origins) {
  
  # Expanding training window: 1971 through the current origin
  training_data <- window(
    ghana_ts,
    end = origin
  )
  
  # Actual observations for the next five years
  test_data <- window(
    ghana_ts,
    start = origin + 1,
    end = origin + forecast_horizon
  )
  
  actual_values <- as.numeric(test_data)
  
  # Skip the origin if five actual observations are unavailable
  if (length(actual_values) != forecast_horizon) {
    next
  }
  
  # Naive benchmark
  naive_forecast <- naive(
    training_data,
    h = forecast_horizon
  )
  
  # Drift benchmark
  drift_forecast <- rwf(
    training_data,
    h = forecast_horizon,
    drift = TRUE
  )
  
  # Historical-growth benchmark
  average_log_growth <- mean(
    diff(log(as.numeric(training_data))),
    na.rm = TRUE
  )
  
  last_training_value <- as.numeric(
    tail(training_data, 1)
  )
  
  historical_growth_forecast <-
    last_training_value *
    exp(average_log_growth * (1:forecast_horizon))
  
  # ARIMA forecasts
  arima_011_forecast <- get_arima_forecast(
    training_data,
    c(0, 1, 1),
    forecast_horizon
  )
  
  arima_111_forecast <- get_arima_forecast(
    training_data,
    c(1, 1, 1),
    forecast_horizon
  )
  
  arima_212_forecast <- get_arima_forecast(
    training_data,
    c(2, 1, 2),
    forecast_horizon
  )
  
  # Put all forecasts into one list
  forecasts <- list(
    "Naive" = as.numeric(naive_forecast$mean),
    "Drift" = as.numeric(drift_forecast$mean),
    "Historical Growth" = historical_growth_forecast,
    "ARIMA(0,1,1)" = arima_011_forecast,
    "ARIMA(1,1,1)" = arima_111_forecast,
    "ARIMA(2,1,2)" = arima_212_forecast
  )
  
  # MASE denominator calculated using the current training period
  mase_scale <- mean(
    abs(diff(as.numeric(training_data))),
    na.rm = TRUE
  )
  
  # Save errors for every method and horizon
  for (model_name in names(forecasts)) {
    
    predicted_values <- forecasts[[model_name]]
    errors <- predicted_values - actual_values
    
    validation_list[[result_number]] <- data.frame(
      Origin = origin,
      Forecast_Year = origin + (1:forecast_horizon),
      Horizon = 1:forecast_horizon,
      Model = model_name,
      Actual = actual_values,
      Forecast = predicted_values,
      Error = errors,
      Absolute_Error = abs(errors),
      Squared_Error = errors^2,
      Scaled_Absolute_Error = abs(errors) / mase_scale
    )
    
    result_number <- result_number + 1
  }
}

#Combine the results
validation_results <- do.call(
  rbind,
  validation_list
)

row.names(validation_results) <- NULL
head(validation_results)
nrow(validation_results)

summary(validation_results[, c("Actual", "Forecast")])

#Calculate overall accuracy for each method
results_by_model <- split(
  validation_results,
  validation_results$Model
)

validation_summary <- do.call(
  rbind,
  lapply(results_by_model, function(model_data) {
    
    valid_rows <- complete.cases(
      model_data$Actual,
      model_data$Forecast
    )
    
    model_data <- model_data[valid_rows, ]
    
    data.frame(
      Model = model_data$Model[1],
      Forecasts = nrow(model_data),
      MAE = mean(model_data$Absolute_Error),
      RMSE = sqrt(mean(model_data$Squared_Error)),
      Bias = mean(model_data$Error),
      MASE = mean(model_data$Scaled_Absolute_Error)
    )
  })
)

row.names(validation_summary) <- NULL

validation_summary <- validation_summary[
  order(validation_summary$RMSE),
]

validation_summary

#Measure consistency across forecast origins
#First, calculate a separate RMSE for each model at each origin:
origin_rmse <- aggregate(
  Squared_Error ~ Model + Origin,
  data = validation_results,
  FUN = function(x) sqrt(mean(x, na.rm = TRUE))
)

names(origin_rmse)[3] <- "Origin_RMSE"

head(origin_rmse)

#Then summarize the variability of those RMSE values:
consistency_list <- split(
  origin_rmse,
  origin_rmse$Model
)

consistency_summary <- do.call(
  rbind,
  lapply(consistency_list, function(model_data) {
    
    data.frame(
      Model = model_data$Model[1],
      Average_Origin_RMSE = mean(
        model_data$Origin_RMSE,
        na.rm = TRUE
      ),
      SD_Origin_RMSE = sd(
        model_data$Origin_RMSE,
        na.rm = TRUE
      ),
      Worst_Origin_RMSE = max(
        model_data$Origin_RMSE,
        na.rm = TRUE
      )
    )
  })
)

row.names(consistency_summary) <- NULL

#Add the consistency measures to the main table:
final_validation_table <- merge(
  validation_summary,
  consistency_summary,
  by = "Model"
)

final_validation_table <- final_validation_table[
  order(final_validation_table$RMSE),
]

row.names(final_validation_table) <- NULL

final_validation_table

#Compare accuracy by forecast horizon
#This determines whether a method performs better for one-year forecasts but worse for five-year forecasts.
horizon_groups <- split(
  validation_results,
  list(
    validation_results$Model,
    validation_results$Horizon
  ),
  drop = TRUE
)

horizon_summary <- do.call(
  rbind,
  lapply(horizon_groups, function(model_data) {
    
    valid_rows <- complete.cases(
      model_data$Actual,
      model_data$Forecast
    )
    
    model_data <- model_data[valid_rows, ]
    
    data.frame(
      Model = model_data$Model[1],
      Horizon = model_data$Horizon[1],
      MAE = mean(model_data$Absolute_Error),
      RMSE = sqrt(mean(model_data$Squared_Error)),
      Bias = mean(model_data$Error),
      MASE = mean(model_data$Scaled_Absolute_Error)
    )
  })
)

row.names(horizon_summary) <- NULL

horizon_summary <- horizon_summary[
  order(horizon_summary$Horizon, horizon_summary$RMSE),
]

horizon_summary

#Save the results
dir.create(
  here("results"),
  showWarnings = FALSE,
  recursive = TRUE
)

write.csv(
  validation_results,
  here("results", "rolling_origin_predictions.csv"),
  row.names = FALSE
)

write.csv(
  final_validation_table,
  here("results", "rolling_origin_model_comparison.csv"),
  row.names = FALSE
)

write.csv(
  horizon_summary,
  here("results", "rolling_origin_by_horizon.csv"),
  row.names = FALSE
)

#Check Diagnostics and Explain Forecast Uncertainty

#Recheck the ARIMA diagnostics
checkresiduals(fit_111)
checkresiduals(fit_212)

#Verify the historical-growth calculation
#Fit the method using the complete series:
average_log_growth <- mean(
  diff(log(as.numeric(ghana_ts))),
  na.rm = TRUE
)

annual_growth_rate <- exp(average_log_growth) - 1

average_log_growth
annual_growth_rate
100 * annual_growth_rate

#Generate the five-year point forecasts:
forecast_horizon <- 5

last_observation <- as.numeric(
  tail(ghana_ts, 1)
)

historical_growth_forecast <-
  last_observation *
  exp(average_log_growth * (1:forecast_horizon))

forecast_years <-
  (end(ghana_ts)[1] + 1):
  (end(ghana_ts)[1] + forecast_horizon)

final_forecast_table <- data.frame(
  Year = forecast_years,
  Forecast = historical_growth_forecast
)

final_forecast_table

#Create reusable metric functions
calculate_metrics <- function(
    actual,
    predicted,
    training_data
) {
  
  errors <- predicted - actual
  
  mase_scale <- mean(
    abs(diff(as.numeric(training_data))),
    na.rm = TRUE
  )
  
  data.frame(
    MAE = mean(abs(errors), na.rm = TRUE),
    RMSE = sqrt(mean(errors^2, na.rm = TRUE)),
    Bias = mean(errors, na.rm = TRUE),
    MASE = mean(abs(errors), na.rm = TRUE) /
      mase_scale
  )
}

test_actual <- c(20, 22, 24)
test_predicted <- c(19, 23, 22)

calculate_metrics(
  actual = test_actual,
  predicted = test_predicted,
  training_data = ghana_ts
)

#Verify that all values use the same scale
range(ghana_ts)
range(historical_growth_forecast)
summary(validation_results$Actual)
summary(validation_results$Forecast)

#save outputs
write.csv(
  final_forecast_table,
  here(
    "results",
    "historical_growth_five_year_forecast.csv"
  ),
  row.names = FALSE
)

#save all the plots

#Historical emissions plot
png(
  here("figures", "ghana_emissions_history.png"),
  width = 1200,
  height = 800,
  res = 150
)

plot(
  ghana_ts,
  type = "o",
  pch = 16,
  col = "black",
  main = "Ghana Greenhouse Gas Emissions, 1971–2023",
  xlab = "Year",
  ylab = "GHG emissions"
)

grid()

dev.off()

#ARIMA(1,1,1) diagnostic plot
png(
  here("figures", "arima_111_diagnostics.png"),
  width = 1400,
  height = 1000,
  res = 150
)

checkresiduals(fit_111)

dev.off()

#ARIMA(2,1,2) diagnostic plot
png(
  here("figures", "arima_212_diagnostics.png"),
  width = 1400,
  height = 1000,
  res = 150
)

checkresiduals(fit_212)

dev.off()

#Day 4 holdout-comparison plot
png(
  here("figures", "holdout_forecast_comparison.png"),
  width = 1400,
  height = 900,
  res = 150
)

matplot(
  forecast_plot_data$Year,
  forecast_plot_data[, -1],
  type = "o",
  lty = 1,
  pch = 1:7,
  col = 1:7,
  xlab = "Year",
  ylab = "GHG emissions",
  main = "Five-Year Holdout Forecast Comparison"
)

legend(
  "topleft",
  legend = names(forecast_plot_data)[-1],
  col = 1:7,
  lty = 1,
  pch = 1:7,
  cex = 0.75
)

grid()

dev.off()

#Rolling-validation RMSE comparison
png(
  here("figures", "rolling_validation_rmse.png"),
  width = 1200,
  height = 800,
  res = 150
)

bar_colors <- ifelse(
  final_validation_table$Model == "Historical Growth",
  "darkgreen",
  "gray60"
)

barplot(
  final_validation_table$RMSE,
  names.arg = final_validation_table$Model,
  col = bar_colors,
  las = 2,
  ylab = "Rolling-validation RMSE",
  main = "Rolling-Origin Forecast Accuracy",
  ylim = c(
    0,
    max(final_validation_table$RMSE) * 1.15
  )
)

grid(nx = NA, ny = NULL)

dev.off()

#Final historical-growth forecast plot
last_year <- end(ghana_ts)[1]
last_observation <- as.numeric(tail(ghana_ts, 1))

png(
  here("figures", "final_historical_growth_forecast.png"),
  width = 1400,
  height = 900,
  res = 150
)

plot(
  ghana_ts,
  type = "l",
  lwd = 2,
  col = "black",
  xlim = c(start(ghana_ts)[1], max(forecast_years)),
  ylim = range(
    c(
      as.numeric(ghana_ts),
      historical_growth_forecast
    )
  ),
  main = "Five-Year Forecast of Ghana GHG Emissions",
  xlab = "Year",
  ylab = "GHG emissions"
)

# Connect the final observation to the forecasts
lines(
  c(last_year, forecast_years),
  c(last_observation, historical_growth_forecast),
  type = "o",
  pch = 16,
  lwd = 2,
  col = "blue"
)

# Mark the end of the observed period
abline(
  v = last_year,
  lty = 2,
  col = "gray40"
)

legend(
  "topleft",
  legend = c(
    "Observed emissions",
    "Historical-growth forecast",
    "Forecast begins"
  ),
  col = c("black", "blue", "gray40"),
  lty = c(1, 1, 2),
  lwd = c(2, 2, 1),
  pch = c(NA, 16, NA),
  bty = "n"
)

grid()

dev.off()