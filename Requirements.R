required_packages <- c(
  "astsa",
  "forecast",
  "here",
  "readxl"
)

packages_to_install <- required_packages[
  !required_packages %in% installed.packages()[, "Package"]
]

if (length(packages_to_install) > 0) {
  install.packages(packages_to_install)
}