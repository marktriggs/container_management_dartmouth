$(function () {

  function ExtentCalculatorForm() {}

  ExtentCalculatorForm.prototype.init_form = function() {
    $('.create-extent-btn').on('click', function (event) {
      $('[id$=_extents_]').find(".btn")[1].click();

      var extent_form = $('[id$=_extents_]').find(".subrecord-form-fields").last();

      extent_form.find("[id$=__portion_]").val($('#extent_portion_').val());
      extent_form.find("[id$=__number_]").val($('#extent_number_').val());
      extent_form.find("[id$=__extent_type_]").val($('#extent_extent_type_').val());
      extent_form.find("[id$=__container_summary_]").val($('#extent_container_summary_').val());
      extent_form.find("[id$=__physical_details_]").val($('#extent_physical_details_').val());
      extent_form.find("[id$=__dimensions_]").val($('#extent_dimensions_').val());

      $modal.modal("hide");
    });
  }

  var init = function () {
    $('.extent-calculator-btn').on('click', function (event) {
      var dialog_content = AS.renderTemplate("extent_calculator_show_calculation_template");

      $modal = AS.openCustomModal("extentCalculationModal", "Extent Calculation", dialog_content, 'full');

      $.ajax({
        url:"/plugins/extent_calculator/",
        data: {record_uri: $("#extent_calculator_show_calculation_template").attr("record_uri"),
	       referrer: document.location.href},
        type: "get",
        success: function(html) {
          $("#show_calculation_results").html(html);
          var extentCalculatorForm = new ExtentCalculatorForm();
          extentCalculatorForm.init_form();
        },
        error: function(jqXHR, textStatus, errorThrown) {
          alert("boo");
        }
      });
    });

  }

  init();

});
