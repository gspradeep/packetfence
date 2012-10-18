function init() {
    $('.datepicker').datepicker({
        endDate: new Date() // today
    });

    /* Search */
    $('form[name="simpleSearch"]').submit(function(event) {
        var form = $(this);
        var results = $('#results');
        results.fadeTo('fast', 0.5);
        $.ajax({
            type: 'POST',
            url: form.attr('action'),
            data: { filter: $('#simpleString').val() }
        }).done(function(data) {
            results.html(data);
            results.stop();
            results.fadeTo('fast', 1.0);
        }).fail(function(jqXHR) {
            if (jqXHR.status == 401) {
                // Unauthorized; redirect to URL specified in the location header
                window.location.href = jqXHR.getResponseHeader('Location');
            }
            else {
                var obj = $.parseJSON(jqXHR.responseText);
                showPermanentError($('#results'), obj.status_msg);
            }
        });
        
        return false;
    });

    /* Sort the search results */
    $('#results').on('click', 'thead a', function(event) {
        var url = $(this).attr('href');
        var results = $('#results');
        results.fadeTo('fast', 0.5);
        $.ajax(url)
        .done(function(data) {
            results.html(data);
            results.stop();
            results.fadeTo('fast', 1.0);
        })
        .fail(function(jqXHR) {
            if (jqXHR.status == 401) {
                // Unauthorized; redirect to URL specified in the location header
                window.location.href = jqXHR.getResponseHeader('Location');
            }
            else {
                var obj = $.parseJSON(jqXHR.responseText);
                showPermanentError($('#results'), obj.status_msg);
            }
        });

        return false;
    });

    /* View a node (show the modal editor) */
    $('#results').on('click', '[href*="#modalNode"]', function(event) {
        var url = $(this).attr('href');
        $.ajax(url)
        .done(function(data) {
            $('body').append(data);
            $('#modalNode').modal({show: true});
            $('#modalNode .chzn-select').chosen();
            $('#modalNode .chzn-deselect').chosen({allow_single_deselect: true});
            $('#modalNode .timepicker-default').each(function() {
                // Keep the placeholder visible if the input has no value
                var defaultTime = $(this).val().length? 'value' : false;
                $(this).timepicker({ defaultTime: defaultTime, showSeconds: false, showMeridian: false });
            });
            $('#modalNode .datepicker').datepicker();
            $('#modalNode a[href="#nodeHistory"]').on('shown', function () {
                if ($('#nodeHistory .chart').children().length == 0)
                    drawGraphs();
            });
            $('#modalNode').on('hidden', function (eventObject) {
                // Destroy the modal unless the event is coming from
                // an input field (See bootstrap-timepicker.js)
                if (eventObject.target.tagName != 'INPUT') {
                    $(this).remove();
                    // Remove the 'pickers' appended to the body
                    $('.datepicker').remove();
                    $('.bootstrap-timepicker').remove();
                }
            });
        })
        .fail(function(jqXHR) {
            if (jqXHR.status == 401) {
                // Unauthorized; redirect to URL specified in the location header
                window.location.href = jqXHR.getResponseHeader('Location');
            }
            else {
                var obj = $.parseJSON(jqXHR.responseText);
                showError($('#results'), obj.status_msg);
            }
        });

        return false;
    });

    /* Save a node (from the modal editor) */
    $('body').on('click', '#updateNode', function(event) {
        var btn = $(this),
        modal = $('#modalNode'),
        form = modal.find('form').first(),
        modal_body = modal.find('.modal-body'),
        url = $(this).attr('href'),
        valid = false;

        btn.button('loading');
        valid = isFormValid(form);
        if (valid) {
        $.ajax({
            type: 'POST',
            url: url,
            data: form.serialize()
        }).done(function(data) {
            // TODO : refresh search results
            modal.modal('hide');
        }).fail(function(jqXHR) {
            if (jqXHR.status == 401) {
                // Unauthorized; redirect to URL specified in the location header
                window.location.href = jqXHR.getResponseHeader('Location');
            }
            else {
                btn.button('reset');
                var obj = $.parseJSON(jqXHR.responseText);
                resetAlert(modal_body);
                showPermanentError(modal_body.children().first(), obj.status_msg);
            }
        });
        }

        return false;
    });

    /* Delete a node (from the modal editor) */
    $('body').on('click', '#deleteNode', function(event) {
        alert("delete node");
        return false;
    });

    /* Initial search */
    $.ajax('/node/search')
    .done(function(data) {
        var results = $('#results');
        results.html(data);
    })
    .fail(function(jqXHR) {
        if (jqXHR.status == 401) {
            // Unauthorized; redirect to URL specified in the location header
            window.location.href = jqXHR.getResponseHeader('Location');
        }
        else {
            var obj = $.parseJSON(jqXHR.responseText);
            showError($('#results'), obj.status_msg);
        }
    });
}
